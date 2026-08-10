# Installation tokens

Mint short-lived GitHub App tokens without going through HTTP.

## Overview

A GitHub App authenticates to a repository with an *installation token*: a credential that GitHub
issues against an installation and expires after one hour. It is what a `git clone` of a private
repository authenticates with.

`app.gitHubAccess` mints them in-process:

```swift
let token = try await app.gitHubAccess.installationToken(for: installationID)

let url = "https://x-access-token:\(token.token)@github.com/octocat/hello-world.git"
```

### No configuration step required

`app.gitHubAccess` is available on any `Application`, whether or not `configureAccessServer` has been
called. Code embedding this package to reach GitHub does not have to mount OpenAPI routes, a
redirect page, and `FileMiddleware` to get a token — and, more to the point, a token request cannot
fail because the HTTP server is down or still starting.

When `configureAccessServer` *is* called it shares the same instance, so `POST /github/token` and
in-process callers draw on one cache.

### Caching

Tokens are cached per installation and reused until they come within
``GitHubAccessConfiguration/refreshLeeway`` — five minutes by default — of expiry. Refreshing early
rather than at expiry means a long `git clone` cannot start with a valid token and finish with an
expired one.

Concurrent requests for the same installation share a single refresh rather than each minting their
own token.

```swift
app.gitHubAccess.configuration.refreshLeeway = 10 * 60
app.gitHubAccess.configuration.userAgent = "MyApp"
```

Set the configuration during application configuration, before the first token is requested.

### When GitHub rejects a cached token

Nothing stops a token being revoked before it expires. If GitHub answers a `git` operation with a
401, drop the cached token and try once more:

```swift
await app.gitHubAccess.invalidateInstallationToken(for: installationID)
let token = try await app.gitHubAccess.installationToken(for: installationID)
```

`refreshInstallationToken(for:)` does both in one call. `invalidateInstallationTokens()` clears the
whole cache.

### Configuring the App credentials

`GITHUB_APP_ID` is required. The private key is read from `GITHUB_PRIVATE_KEY_PATH` when it is set,
and otherwise from `GITHUB_PRIVATE_KEY`, which holds the PEM inline — containers and CI runners
usually inject secrets as environment variables rather than files. A single-line inline PEM has its
escaped `\n` sequences restored, so the common secret-store shape works.

Configuration is resolved on first use, so a token request against an unconfigured process throws
`Abort(.badRequest)` naming the missing variable. `configureAccessServer` resolves it eagerly
instead, so a misconfigured server fails at start-up rather than on the first token request.

## Topics

### Configuration

- ``GitHubAccessConfiguration``
- ``GitHubInstallationToken``
