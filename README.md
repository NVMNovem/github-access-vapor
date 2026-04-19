<picture>
  <source srcset="https://github.com/user-attachments/assets/38817448-f9ae-47cd-9e37-34292f9f1746" media="(prefers-color-scheme: light)"/>
  <source srcset="https://github.com/user-attachments/assets/b1dd11dd-98cf-402b-bc11-de31b73302e0"  media="(prefers-color-scheme: dark)"/>
  <img src="https://github.com/user-attachments/assets/38817448-f9ae-47cd-9e37-34292f9f1746" alt="GitHubAccessVapor"/>
</picture>

GitHubAccessVapor is a Swift package for integrating GitHub App setup and installation-token generation into Vapor projects.

It provides a lightweight API to configure a GitHub access server, validate token requests, and issue GitHub installation tokens.

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
    )
]
```

## Basic usage

Configure your Vapor app:

```swift
import Vapor
import GitHubAccess

public func configure(_ app: Application) async throws {
    try await app.configureAccessServer(project: "MyApp", accent: "34C759")
}
```

Set the required environment variables before starting the server:

```bash
export GITHUB_APP_ID="<your-github-app-id>"
export GITHUB_PRIVATE_KEY_PATH="/absolute/path/to/private-key.pem"
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
