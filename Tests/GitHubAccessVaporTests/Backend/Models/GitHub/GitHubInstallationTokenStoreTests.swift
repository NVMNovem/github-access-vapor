//
//  GitHubInstallationTokenStoreTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation
import Testing

import Vapor
import VaporTesting

@testable import GitHubAccessVapor

@Suite("GitHubInstallationTokenStore")
struct GitHubInstallationTokenStoreTests {

    /// Counts how many times a token was minted, and hands out tokens with a chosen lifetime.
    private actor MintCounter {

        private(set) var calls: [Int64] = []
        private(set) var userAgents: [String] = []

        private var lifetime: TimeInterval
        private var sequence = 0

        init(lifetime: TimeInterval = 3600) {
            self.lifetime = lifetime
        }

        func setLifetime(_ lifetime: TimeInterval) {
            self.lifetime = lifetime
        }

        func mint(for installationID: Int64, userAgent: String) -> GitHubInstallationToken {
            calls.append(installationID)
            userAgents.append(userAgent)
            sequence += 1

            return GitHubInstallationToken(
                token: "ghs_token_\(sequence)",
                expiresAt: Date().addingTimeInterval(lifetime)
            )
        }
    }

    @Test("mints once and reuses the token while it is comfortably valid")
    func reusesValidToken() async throws {
        try await withApp { app in
            let counter = MintCounter(lifetime: 3600)
            let store = GitHubInstallationTokenStore(application: app) { installationID, userAgent in
                await counter.mint(for: installationID, userAgent: userAgent)
            }

            let first = try await store.token(for: 1, configuration: GitHubAccessConfiguration())
            let second = try await store.token(for: 1, configuration: GitHubAccessConfiguration())

            #expect(first.token == second.token)
            let calls = await counter.calls
            #expect(calls == [1])
        }
    }

    @Test("caches per installation")
    func cachesPerInstallation() async throws {
        try await withApp { app in
            let counter = MintCounter(lifetime: 3600)
            let store = GitHubInstallationTokenStore(application: app) { installationID, userAgent in
                await counter.mint(for: installationID, userAgent: userAgent)
            }

            let first = try await store.token(for: 1, configuration: GitHubAccessConfiguration())
            let second = try await store.token(for: 2, configuration: GitHubAccessConfiguration())
            _ = try await store.token(for: 1, configuration: GitHubAccessConfiguration())

            #expect(first.token != second.token)
            let calls = await counter.calls
            #expect(calls == [1, 2])
        }
    }

    @Test("refreshes before expiry rather than at it")
    func refreshesWithinLeeway() async throws {
        try await withApp { app in
            // Four minutes of life left, against the default five-minute refresh window.
            let counter = MintCounter(lifetime: 4 * 60)
            let store = GitHubInstallationTokenStore(application: app) { installationID, userAgent in
                await counter.mint(for: installationID, userAgent: userAgent)
            }

            let first = try await store.token(for: 1, configuration: GitHubAccessConfiguration())
            let second = try await store.token(for: 1, configuration: GitHubAccessConfiguration())

            #expect(first.token != second.token)
            let calls = await counter.calls
            #expect(calls == [1, 1])
        }
    }

    @Test("keeps a token that outlives the refresh window")
    func keepsTokenOutsideLeeway() async throws {
        try await withApp { app in
            let counter = MintCounter(lifetime: 6 * 60)
            let store = GitHubInstallationTokenStore(application: app) { installationID, userAgent in
                await counter.mint(for: installationID, userAgent: userAgent)
            }

            _ = try await store.token(for: 1, configuration: GitHubAccessConfiguration())
            _ = try await store.token(for: 1, configuration: GitHubAccessConfiguration())

            let calls = await counter.calls
            #expect(calls == [1])
        }
    }

    @Test("honours a custom refresh leeway")
    func honoursCustomLeeway() async throws {
        try await withApp { app in
            let counter = MintCounter(lifetime: 10 * 60)
            let store = GitHubInstallationTokenStore(application: app) { installationID, userAgent in
                await counter.mint(for: installationID, userAgent: userAgent)
            }
            let configuration = GitHubAccessConfiguration(refreshLeeway: 20 * 60)

            _ = try await store.token(for: 1, configuration: configuration)
            _ = try await store.token(for: 1, configuration: configuration)

            let calls = await counter.calls
            #expect(calls == [1, 1])
        }
    }

    @Test("coalesces concurrent requests for the same installation")
    func coalescesConcurrentRequests() async throws {
        try await withApp { app in
            let counter = MintCounter(lifetime: 3600)
            let store = GitHubInstallationTokenStore(application: app) { installationID, userAgent in
                // Long enough that every task piles up on the same refresh.
                try? await Task.sleep(for: .milliseconds(50))
                return await counter.mint(for: installationID, userAgent: userAgent)
            }

            let tokens = try await withThrowingTaskGroup(of: String.self) { group in
                for _ in 0..<16 {
                    group.addTask {
                        try await store.token(for: 1, configuration: GitHubAccessConfiguration()).token
                    }
                }

                return try await group.reduce(into: Set<String>()) { $0.insert($1) }
            }

            #expect(tokens.count == 1)
            let calls = await counter.calls
            #expect(calls == [1])
        }
    }

    @Test("replaces the cached token on an explicit refresh")
    func explicitRefreshReplacesCachedToken() async throws {
        try await withApp { app in
            let counter = MintCounter(lifetime: 3600)
            let store = GitHubInstallationTokenStore(application: app) { installationID, userAgent in
                await counter.mint(for: installationID, userAgent: userAgent)
            }

            let first = try await store.token(for: 1, configuration: GitHubAccessConfiguration())
            let refreshed = try await store.refreshedToken(for: 1, configuration: GitHubAccessConfiguration())
            let afterRefresh = try await store.token(for: 1, configuration: GitHubAccessConfiguration())

            #expect(first.token != refreshed.token)
            #expect(afterRefresh.token == refreshed.token)
        }
    }

    @Test("mints again after the cached token is invalidated")
    func invalidationForcesNewToken() async throws {
        try await withApp { app in
            let counter = MintCounter(lifetime: 3600)
            let store = GitHubInstallationTokenStore(application: app) { installationID, userAgent in
                await counter.mint(for: installationID, userAgent: userAgent)
            }

            _ = try await store.token(for: 1, configuration: GitHubAccessConfiguration())
            await store.removeToken(for: 1)
            _ = try await store.token(for: 1, configuration: GitHubAccessConfiguration())

            let calls = await counter.calls
            #expect(calls == [1, 1])
        }
    }

    @Test("passes the configured User-Agent through to the mint")
    func passesConfiguredUserAgent() async throws {
        try await withApp { app in
            let counter = MintCounter(lifetime: 3600)
            let store = GitHubInstallationTokenStore(application: app) { installationID, userAgent in
                await counter.mint(for: installationID, userAgent: userAgent)
            }

            _ = try await store.token(
                for: 1,
                configuration: GitHubAccessConfiguration(userAgent: "MyApp")
            )

            let userAgents = await counter.userAgents
            #expect(userAgents == ["MyApp"])
        }
    }

    @Test("does not cache a failed mint")
    func doesNotCacheFailures() async throws {
        try await withApp { app in
            let counter = MintCounter(lifetime: 3600)
            let store = GitHubInstallationTokenStore(application: app) { installationID, userAgent in
                let calls = await counter.calls
                guard !calls.isEmpty else {
                    _ = await counter.mint(for: installationID, userAgent: userAgent)
                    throw Abort(.internalServerError, reason: "GitHub said no.")
                }

                return await counter.mint(for: installationID, userAgent: userAgent)
            }

            await #expect(throws: (any Error).self) {
                _ = try await store.token(for: 1, configuration: GitHubAccessConfiguration())
            }

            let token = try await store.token(for: 1, configuration: GitHubAccessConfiguration())
            #expect(token.token.hasPrefix("ghs_token_"))
        }
    }
}
