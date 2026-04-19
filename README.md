<picture>
  <source srcset="https://github.com/user-attachments/assets/38817448-f9ae-47cd-9e37-34292f9f1746" media="(prefers-color-scheme: light)"/>
  <source srcset="https://github.com/user-attachments/assets/b1dd11dd-98cf-402b-bc11-de31b73302e0"  media="(prefers-color-scheme: dark)"/>
  <img src="https://github.com/user-attachments/assets/38817448-f9ae-47cd-9e37-34292f9f1746" alt="GitHubAccess"/>
</picture>

Swift Async Scheduler is a small, dependency-free Swift package for scheduling and running asynchronous jobs.

This package provides a lightweight API for creating recurring and scheduled async jobs, intended for use in server- and app-side Swift code. It intentionally avoids external dependencies — it's written in plain Swift and integrates with the Swift concurrency model.

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
            .product(name: "GitHubAccess", package: "github-access-vapor")
        ]
    )
]
```

## Basic usage

#### ViewModifier
```swift
import GitHubAccess
```

#### Scene
```swift
import GitHubAccess
```
