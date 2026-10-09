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

    internal let application: Application
    private let minter: Minter?

    private var service: GitHubAppTokenService?
    private var credentials: GitHubAppCredentials?
    private var cachedAppSlug: String?
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
            let service = try resolvedService(configuration: configuration)
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

        _ = try resolvedService(configuration: configuration)
    }

    /// Signs with `credentials` from now on, and forgets every cached token: they belonged to the
    /// previous App and are useless under the new one.
    internal func setCredentials(_ credentials: GitHubAppCredentials?) {
        self.credentials = credentials
        cachedAppSlug = nil
        service = nil
        tokens.removeAll()
    }

    /// The App's slug, fetched with `fetch` the first time and remembered.
    internal func appSlug(fetch: @Sendable () async throws -> String) async throws -> String {
        if let cachedAppSlug { return cachedAppSlug }
        let slug = try await fetch()
        cachedAppSlug = slug
        return slug
    }

    /// A JWT that authenticates as the App, for the endpoints that are about the App or its
    /// installations rather than something an installation can see.
    internal func appJWT(configuration: GitHubAccessConfiguration) async throws -> String {
        try await resolvedService(configuration: configuration).githubAppJWT()
    }

    /// The token service is resolved on first use so that `app.gitHubAccess` is available
    /// without any configuration step, and rebuilt when the configured `User-Agent`, API URL or
    /// credentials change.
    private func resolvedService(configuration: GitHubAccessConfiguration) throws -> GitHubAppTokenService {
        if let service, service.userAgent == configuration.userAgent, service.apiBaseURL == configuration.apiBaseURL {
            return service
        }

        let service: GitHubAppTokenService
        if let credentials {
            service = GitHubAppTokenService(
                app: application, credentials: credentials,
                userAgent: configuration.userAgent, apiBaseURL: configuration.apiBaseURL
            )
        } else {
            service = try GitHubAppTokenService(
                app: application, userAgent: configuration.userAgent, apiBaseURL: configuration.apiBaseURL
            )
        }
        self.service = service

        return service
    }
}
