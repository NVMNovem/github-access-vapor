//
//  GitHubInstallationTokenStore.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

import Vapor

/// Caches GitHub installation tokens per installation and mints new ones on demand.
///
/// Installation tokens are valid for one hour. Callers typically make several requests against the
/// same installation in quick succession, so minting one token per request would waste calls and run
/// into GitHub's rate limits. Tokens are therefore reused until they come within
/// ``GitHubAccessConfiguration/refreshLeeway`` of expiry — refreshing early means a long-running
/// operation cannot start with a valid token and finish with an expired one.
///
/// Concurrent requests for the same installation share a single refresh rather than each minting
/// their own token.
internal actor GitHubInstallationTokenStore {

    /// Mints one token for an installation, addressing GitHub with the given `User-Agent`.
    internal typealias Minter = @Sendable (Int64, String) async throws -> GitHubInstallationToken

    private let application: Application
    private let minter: Minter?

    private var service: GitHubAppTokenService?
    private var tokens: [Int64: GitHubInstallationToken] = [:]
    private var refreshes: [Int64: Task<GitHubInstallationToken, Swift.Error>] = [:]

    /// - Parameter minter: Replaces the call to GitHub. Only tests pass this.
    internal init(application: Application, minter: Minter? = nil) {
        self.application = application
        self.minter = minter
    }

    /// Returns a cached token when one is still comfortably valid, and mints a new one otherwise.
    internal func token(
        for installationID: Int64,
        configuration: GitHubAccessConfiguration,
        now: Date = Date()
    ) async throws -> GitHubInstallationToken {
        if let cached = tokens[installationID],
           cached.expiresAt.timeIntervalSince(now) > configuration.refreshLeeway {
            return cached
        }

        return try await refreshedToken(for: installationID, configuration: configuration)
    }

    /// Mints a new token, ignoring — and replacing — any cached one.
    @discardableResult
    internal func refreshedToken(
        for installationID: Int64,
        configuration: GitHubAccessConfiguration
    ) async throws -> GitHubInstallationToken {
        if let inFlight = refreshes[installationID] {
            return try await inFlight.value
        }

        let refresh: Task<GitHubInstallationToken, Swift.Error>
        if let minter {
            let userAgent = configuration.userAgent
            refresh = Task { try await minter(installationID, userAgent) }
        } else {
            let service = try resolvedService(userAgent: configuration.userAgent)
            refresh = Task { try await service.createInstallationToken(for: installationID) }
        }
        refreshes[installationID] = refresh
        defer { refreshes[installationID] = nil }

        let token = try await refresh.value
        tokens[installationID] = token

        return token
    }

    internal func removeToken(for installationID: Int64) {
        tokens[installationID] = nil
    }

    internal func removeAllTokens() {
        tokens.removeAll()
    }

    /// Resolves — and validates — the GitHub App configuration without minting a token.
    internal func prepare(configuration: GitHubAccessConfiguration) throws {
        guard minter == nil else { return }

        _ = try resolvedService(userAgent: configuration.userAgent)
    }

    /// The token service is resolved on first use so that `app.gitHubAccess` is available
    /// without any configuration step, and rebuilt when the configured `User-Agent` changes.
    private func resolvedService(userAgent: String) throws -> GitHubAppTokenService {
        if let service, service.userAgent == userAgent {
            return service
        }

        let service = try GitHubAppTokenService(app: application, userAgent: userAgent)
        self.service = service

        return service
    }
}
