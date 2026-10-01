<picture>
  <source srcset="https://github.com/user-attachments/assets/38817448-f9ae-47cd-9e37-34292f9f1746" media="(prefers-color-scheme: light)"/>
  <source srcset="https://github.com/user-attachments/assets/b1dd11dd-98cf-402b-bc11-de31b73302e0"  media="(prefers-color-scheme: dark)"/>
  <img src="https://github.com/user-attachments/assets/38817448-f9ae-47cd-9e37-34292f9f1746" alt="GitHubAccessVapor"/>
</picture>

GitHubAccessVapor is a Swift package for integrating GitHub App setup, installation-token generation, and webhook delivery into Vapor projects.

It provides a lightweight API to configure a GitHub access server, mint installation tokens in-process, and receive signed GitHub webhooks.

## Platform Compatibility
This Swift package is designed to run on:
- ![macOS](https://github.com/NVMNovem/github-access-vapor/actions/workflows/buildOnMacOS.yml/badge.svg)
- ![Linux](https://github.com/NVMNovem/github-access-vapor/actions/workflows/buildOnLinux.yml/badge.svg)

## Installation

Add `github-access-vapor` as a dependency to your `Package.swift`:

```swift
// Package.swift (snippet)
dependencies: [
    .package(url: "https://github.com/NVMNovem/github-access-vapor", from: "1.0.0")
]

targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "GitHubAccessVapor", package: "github-access-vapor")
        ]
    ),
    .testTarget(
        name: "MyAppTests",
        dependencies: [
            "MyApp",
            .product(name: "GitHubAccessVaporTesting", package: "github-access-vapor")
        ]
    )
]
```

## Basic usage

Configure your Vapor app:

```swift
import Vapor
import GitHubAccessVapor

public func configure(_ app: Application) async throws {
    try await app.configureAccessServer(project: "MyApp", accent: "34C759")
}
```

Set the required environment variables before starting the server:

```bash
export GITHUB_APP_ID="<your-github-app-id>"
export GITHUB_PRIVATE_KEY_PATH="/absolute/path/to/private-key.pem"
```

`GITHUB_PRIVATE_KEY` holds the PEM inline as an alternative, for containers and CI runners that
inject secrets as environment variables. The path wins when both are set.

`configureAccessServer` installs `FileMiddleware` to serve the setup page's `/logo.svg`. Pass
`servesAssets: false` if your application configures its own middleware stack.

If your clients sign in to GitHub themselves with user access tokens and need no installation
token from the server, mount only the setup page GitHub's install redirect lands on. It reads no
GitHub App configuration:

```swift
try await app.configureSetupPage(project: "MyApp", accent: "34C759")
```

Request an installation token:

```bash
curl -X POST http://localhost:4321/github/token \
  -H "Content-Type: application/json" \
  -d '{"installationId": 12345678}'
```

Expected response:

```json
{
  "token": "ghs_...",
  "expiresAt": "2026-04-19T12:34:56Z"
}
```

## Installation tokens, in-process

Code embedding this package does not have to go through HTTP — and should not, since a token request
would then depend on its own web server being up:

```swift
import Vapor
import GitHubAccessVapor

func cloneURL(for repository: String, installationID: Int64, on app: Application) async throws -> String {
    let token = try await app.gitHubAccess.installationToken(for: installationID)

    return "https://x-access-token:\(token.token)@github.com/\(repository).git"
}
```

`app.gitHubAccess` works whether or not `configureAccessServer` has been called, and shares one cache
with `POST /github/token` when it has been. Tokens are cached per installation and replaced five
minutes before GitHub expires them, so a long `git clone` cannot start with a valid token and finish
with an expired one. Concurrent callers share a single refresh.

```swift
app.gitHubAccess.configuration.userAgent = "MyApp"
app.gitHubAccess.configuration.refreshLeeway = 10 * 60

// If GitHub rejects a token the cache still considers valid:
let fresh = try await app.gitHubAccess.refreshInstallationToken(for: installationID)
```

## Webhooks

```swift
import Vapor
import GitHubAccessVapor

public func configure(_ app: Application) async throws {
    try app.configureWebhooks(secret: .environment("GITHUB_WEBHOOK_SECRET"),
                              path: "github", "webhook")

    app.gitHubEvents.on(.release) { event, request in
        guard event.action == .published else { return }

        request.logger.info("\(event.repository.fullName) released \(event.release.tagName)")

        if let installation = event.installation {
            let token = try await request.application.gitHubAccess.installationToken(for: installation.id)
            // …clone or call the GitHub API with `token.token`.
        }
    }
}
```

```bash
export GITHUB_WEBHOOK_SECRET="<your-webhook-secret>"
```

The route verifies `X-Hub-Signature-256` against the **raw** request body — content decoding does not
round-trip byte-identically, and a re-encode invalidates the signature. Comparison is constant time,
using swift-crypto rather than CryptoKit so that Linux is supported.

Deliveries are deduplicated on `X-GitHub-Delivery`, so a GitHub retry does not run your handler
twice. Handlers run after the response has been sent, because GitHub calls a delivery failed at
around ten seconds.

| Situation | Response |
| --- | --- |
| Missing `X-Hub-Signature-256`, `X-GitHub-Event`, `X-GitHub-Delivery`, or body | `400 Bad Request` |
| Signature does not verify | `401 Unauthorized` |
| Already-seen delivery | `200 OK`, not dispatched |
| Verified delivery | `202 Accepted`, dispatched |

`release` is the only event modelled so far. Others arrive by raw name, since `GitHubEventName` is an
open type:

```swift
app.gitHubEvents.on(event: "workflow_run") { delivery, request in
    let payload = try delivery.decode(MyWorkflowRun.self)
}
```

## Testing

`GitHubAccessVaporTesting` signs fixtures the way GitHub signs deliveries:

```swift
import Testing
import GitHubAccessVaporTesting
import GitHubAccessVapor

@Test func rejectsATamperedBody() {
    let body = Data(#"{"action":"published"}"#.utf8)
    let signature = GitHubWebhookSigner.sign(body: body, secret: "test-secret")
    let verifier = GitHubWebhookSignatureVerifier(secret: "test-secret")

    #expect(verifier.isValidSignature(signature, body: body))
    #expect(verifier.isValidSignature(signature, body: Data(#"{"action":"deleted"}"#.utf8)) == false)
}
```

Sign the exact bytes you send: signing an encoded fixture and then sending a re-encoded copy produces
a signature that will not verify.
