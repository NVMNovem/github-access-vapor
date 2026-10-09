# Setting up the GitHub App

Create the App, install it, and keep track of its installations, without a human copying IDs or keys around.

## Overview

A server that acts on GitHub as an App has three setup problems, and each has the same shape: GitHub
sends the administrator's browser back to your server with a URL, and **anyone can type that URL**. So
nothing in a redirect is believed until it is tied to the administrator who started the flow and, where
GitHub can be asked, confirmed by GitHub.

| Step | Flow | The redirect is checked against |
| --- | --- | --- |
| Create the App from a manifest | ``GitHubManifestFlow`` | a single-use `state`, then GitHub (the one-time `code`) |
| Install the App on an account | ``GitHubSetupFlow`` | a single-use `state`, then `GET /app/installations/{id}` with the App's own key |
| Hear about later changes | ``GitHubInstallationEvent`` webhooks | the webhook signature |

### Remembering what you issued

Both flows hand GitHub a `state` and expect it back. A ``GitHubSetupStateStore`` remembers them: each is
unguessable, bound to the administrator (the *subject*) who began the flow, valid for one redemption
and for minutes, and issued for one ``GitHubSetupPurpose`` only. ``InMemoryGitHubSetupStateStore`` is right
for one process; run several instances behind a balancer and the redirect may land on one that did not
issue the value, so provide a store they share.

### Installing

```swift
import Vapor
import GitHubAccessVapor

func configureInstall(_ app: Application) async throws -> GitHubSetupFlow {
    let installations = InMemoryGitHubInstallationStore()

    // GitHub's "Setup URL" for the App points at this route. It sits outside user authentication,
    // because GitHub's redirect carries none: the state is what authenticates it.
    let flow = app.gitHubAccess.mountSetupCallback(
        at: ["github", "installed"],
        states: InMemoryGitHubSetupStateStore(),
        store: installations
    ) { outcome, _ in
        switch outcome {
        case .installed(_, let subject):
            return Response(status: .seeOther, headers: ["Location": "https://console.example.com/github?connected=\(subject)"])
        case .requested:
            return Response(status: .seeOther, headers: ["Location": "https://console.example.com/github?requested=1"])
        }
    }

    app.gitHubAccess.keepInstallations(in: installations)
    return flow
}

// In an authenticated route, for the signed-in administrator:
//     let invitation = try await flow.begin(for: adminID)
//     // send the browser to invitation.url
```

A refused redirect always gets the same `400`, whatever was wrong with it, so the callback cannot be
used to learn which states or installations exist. The reason is in the log.

### Creating the App

The manifest flow is the same in miniature. GitHub only accepts a manifest from a browser the
administrator is signed in to, so ``GitHubManifestFlow/begin(_:owner:for:now:)`` returns the form to render rather
than doing the request itself.

```swift
func configureManifest(_ app: Application) {
    app.gitHubAccess.mountManifestCallback(
        at: ["github", "created"], states: InMemoryGitHubSetupStateStore()
    ) { conversion, subject, request in
        // The App's secrets exist in exactly this one response. Put them in your secret store now.
        let credentials = GitHubAppCredentials(appID: String(conversion.id), privateKeyPEM: conversion.pem)
        await request.application.gitHubAccess.useCredentials(credentials)
        return Response(status: .seeOther, headers: ["Location": "https://console.example.com/github"])
    }
}
```

The package never logs, stores or returns those secrets. ``GitHubAppCredentials`` redacts the key when printed.

### Staying in step with GitHub

Webhooks tell you about installations as they change, but a delivery can be missed while the server is
down. `keepInstallations(in:)` applies `installation` and `installation_repositories` events to a
``GitHubInstallationStore``; `reconcileInstallations(in:)` replaces the contents with what GitHub
lists and reports what differed. Run it at start-up and now and then.

### Calling GitHub

``GitHubInstallationClient`` (from `app.gitHubAccess.client(for:)`) lists repositories and releases and
streams a release asset to disk. It checks the byte count and the SHA-256 GitHub published, writes to a
temporary file first, and never sends the installation token to the storage host GitHub redirects to.
Failures are ``GitHubAPIError`` with a ``GitHubAPIError/Kind`` to decide on.

## Topics

### Flows

- ``GitHubSetupFlow``
- ``GitHubManifestFlow``
- ``GitHubSetupError``

### State and installations

- ``GitHubSetupStateStore``
- ``InMemoryGitHubSetupStateStore``
- ``GitHubSetupPurpose``
- ``GitHubInstallationStore``
- ``InMemoryGitHubInstallationStore``

### Credentials and calls

- ``GitHubAppCredentials``
- ``GitHubInstallationClient``
- ``GitHubAPIError``

### Events

- ``GitHubInstallationEvent``
- ``GitHubInstallationRepositoriesEvent``
