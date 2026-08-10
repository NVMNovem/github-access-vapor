//
//  Application+GitHubAccessTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation
import Testing

import Vapor
import VaporTesting

@testable import GitHubAccessVapor

@Suite("Application.gitHubAccess")
struct ApplicationGitHubAccessTests {

    @Test("hands out one shared instance")
    func sharesASingleInstance() async throws {
        try await withApp { app in
            #expect(app.gitHubAccess.store === app.gitHubAccess.store)
        }
    }

    @Test("survives concurrent first access")
    func concurrentFirstAccessSharesOneInstance() async throws {
        try await withApp { app in
            let stores = await withTaskGroup(of: ObjectIdentifier.self) { group in
                for _ in 0..<32 {
                    group.addTask { ObjectIdentifier(app.gitHubAccess.store) }
                }

                return await group.reduce(into: Set<ObjectIdentifier>()) { $0.insert($1) }
            }

            #expect(stores.count == 1)
        }
    }

    @Test("mints tokens without configureAccessServer having been called")
    func worksWithoutConfigureAccessServer() async throws {
        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": nil,
            "GITHUB_PRIVATE_KEY_PATH": nil,
            "GITHUB_PRIVATE_KEY": nil
        ]) {
            try await withApp { app in
                // No configureAccessServer, no routes, no FileMiddleware: the token path is live
                // regardless, and reaches GitHub App configuration on its own.
                do {
                    _ = try await app.gitHubAccess.installationToken(for: 1)
                    Issue.record("Expected the missing GitHub App configuration to throw.")
                } catch let error as AbortError {
                    #expect(error.reason == "Missing configuration value 'GITHUB_APP_ID'.")
                }
            }
        }
    }

    @Test("configureAccessServer reuses the shared instance")
    func configureAccessServerReusesSharedInstance() async throws {
        let key = try GitHubEnvironment.temporaryPrivateKeyFile()
        defer { try? FileManager.default.removeItem(at: key) }

        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": "42",
            "GITHUB_PRIVATE_KEY_PATH": key.path,
            "GITHUB_PRIVATE_KEY": nil
        ]) {
            try await withApp { app in
                let before = app.gitHubAccess.store
                try await app.configureAccessServer(project: "MyApp", accent: "34C759", servesAssets: false)

                #expect(app.gitHubAccess.store === before)
            }
        }
    }

    @Test("configureAccessServer forwards its User-Agent to the shared configuration")
    func configureAccessServerSetsUserAgent() async throws {
        let key = try GitHubEnvironment.temporaryPrivateKeyFile()
        defer { try? FileManager.default.removeItem(at: key) }

        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": "42",
            "GITHUB_PRIVATE_KEY_PATH": key.path,
            "GITHUB_PRIVATE_KEY": nil
        ]) {
            try await withApp { app in
                #expect(app.gitHubAccess.configuration.userAgent == "GitSyncAccessServer")

                try await app.configureAccessServer(
                    project: "MyApp",
                    accent: "34C759",
                    servesAssets: false,
                    userAgent: "MyApp"
                )

                #expect(app.gitHubAccess.configuration.userAgent == "MyApp")
            }
        }
    }

    @Test("leaves the middleware stack alone when assets are not served")
    func doesNotInstallFileMiddlewareWhenOptedOut() async throws {
        let key = try GitHubEnvironment.temporaryPrivateKeyFile()
        defer { try? FileManager.default.removeItem(at: key) }

        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": "42",
            "GITHUB_PRIVATE_KEY_PATH": key.path,
            "GITHUB_PRIVATE_KEY": nil
        ]) {
            try await withApp { app in
                let before = app.middleware.resolve().count
                try await app.configureAccessServer(
                    project: "MyApp",
                    accent: "34C759",
                    servesAssets: false
                )

                #expect(app.middleware.resolve().count == before)
            }

            try await withApp { app in
                let before = app.middleware.resolve().count
                try await app.configureAccessServer(project: "MyApp", accent: "34C759")

                #expect(app.middleware.resolve().count == before + 1)
            }
        }
    }

    @Test("keeps configuration changes visible across accesses")
    func configurationIsShared() async throws {
        try await withApp { app in
            app.gitHubAccess.configuration.refreshLeeway = 42

            #expect(app.gitHubAccess.configuration.refreshLeeway == 42)
        }
    }
}
