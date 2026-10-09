# ``GitHubAccessVapor``

GitHub App setup, installation tokens, and webhook delivery for Vapor projects.

## Overview

The package does four things:

- **Mints installation tokens**, in-process through `app.gitHubAccess` or over HTTP through
  `POST /github/token` (off unless the host enables it; see ``GitHubTokenAccess``). Tokens are cached per installation and refreshed before they expire.
- **Receives webhooks**, verifying GitHub's signature over the raw request body and handing verified
  deliveries to handlers registered on `app.gitHubEvents`.
- **Sets the App up and calls GitHub**: creates it from a manifest, verifies installations, and lists
  repositories and releases. See <doc:GitHubAppSetup>.
- **Serves the GitHub App setup page** at `/github/setup`, which redirects back into your app after
  an installation completes.

Each is independent. A host that only needs tokens does not have to mount any routes:

```swift
import Vapor
import GitHubAccessVapor

let token = try await app.gitHubAccess.installationToken(for: installationID)
```

A host that wants the full access server calls one function:

```swift
public func configure(_ app: Application) async throws {
    try await app.configureAccessServer(project: "MyApp", accent: "34C759")

    try app.configureWebhooks(secret: .environment("GITHUB_WEBHOOK_SECRET"),
                              path: "github", "webhook")

    app.gitHubEvents.on(.release) { event, request in
        guard event.action == .published else { return }
        request.logger.info("\(event.repository.fullName) released \(event.release.tagName)")
    }
}
```

### Configuration

| Variable | Purpose |
| --- | --- |
| `GITHUB_APP_ID` | The GitHub App's numeric identifier. Required. |
| `GITHUB_PRIVATE_KEY_PATH` | Path to the App's private key in PEM form. |
| `GITHUB_PRIVATE_KEY` | The PEM itself, for environments that inject secrets as variables. Used when no path is set. |
| `GITHUB_WEBHOOK_SECRET` | The webhook signing secret, when using ``GitHubWebhookSecret/environment(_:)``. |

Everything runs on Linux as well as macOS: signature verification uses swift-crypto, never CryptoKit.

### The `Application` surface

These live in extensions on Vapor's `Application`, so they are documented here rather than as
symbols of this module:

| Member | Purpose |
| --- | --- |
| `app.gitHubAccess` | Mints and caches installation tokens. See <doc:GitHubInstallationTokens>. |
| `app.gitHubEvents` | The ``GitHubEventDispatcher`` webhook handlers register on. |
| `app.configureWebhooks(secret:path:)` | Mounts the webhook endpoint. See <doc:GitHubWebhooks>. |
| `app.configureAccessServer(project:accent:servesAssets:userAgent:tokens:)` | Mounts `/health`, `/github/setup`, and `/github/token` when `tokens` allows it (it does not by default). |
| `app.gitHubAccess.setup(states:)`, `.manifest(states:)` | The verified installation and App-creation flows. See <doc:GitHubAppSetup>. |
| `app.gitHubAccess.mountSetupCallback`, `.mountManifestCallback` | Mount the redirect routes for those flows. |
| `app.gitHubAccess.client(for:)`, `.installation(id:)`, `.installations()`, `.appSlug()` | GitHub REST calls as the App and as an installation. |
| `app.gitHubAccess.keepInstallations(in:)`, `.reconcileInstallations(in:)` | Keep a ``GitHubInstallationStore`` current. |
| `app.gitHubAccess.useCredentials(_:)` | Sign with ``GitHubAppCredentials`` instead of the environment. |
| `app.configureSetupPage(project:accent:servesAssets:)` | Mounts only `/github/setup`, for clients that sign in with user tokens. Needs no GitHub App configuration. |

## Topics

### Essentials

- <doc:GitHubInstallationTokens>
- <doc:GitHubWebhooks>
- <doc:GitHubAppSetup>

### Installation tokens

- ``GitHubAccessConfiguration``
- ``GitHubInstallationToken``
- ``GitHubTokenAccess``

### Webhooks

- ``GitHubEventDispatcher``
- ``GitHubWebhookSecret``
- ``GitHubWebhookDelivery``
- ``GitHubWebhookSignatureVerifier``
- ``GitHubWebhookHeader``

### Events

- ``GitHubEventName``
- ``GitHubEventKey``
- ``GitHubWebhookEvent``
- ``GitHubReleaseEvent``
- ``GitHubRelease``
- ``GitHubReleaseAsset``
- ``GitHubRepository``
- ``GitHubUser``
- ``GitHubInstallationReference``
