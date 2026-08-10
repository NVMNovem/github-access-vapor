//
//  Application+GitHubAccess.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

import Vapor
import NIOConcurrencyHelpers

extension Application {

    /// In-process access to GitHub App installation tokens.
    ///
    /// ```swift
    /// let token = try await app.gitHubAccess.installationToken(for: installationID)
    /// ```
    ///
    /// Available without calling `configureAccessServer(project:accent:servesAssets:userAgent:)`:
    /// a host that only needs tokens does not have to mount the OpenAPI routes or the setup page.
    /// When `configureAccessServer` *is* called it shares this same instance, so tokens are cached
    /// once for the whole process.
    public var gitHubAccess: GitHubAccess {
        if let existing = storage[GitHubAccessKey.self] {
            return existing
        }

        let lock = locks.lock(for: GitHubAccessKey.self)
        lock.lock()
        defer { lock.unlock() }

        if let existing = storage[GitHubAccessKey.self] {
            return existing
        }

        let access = GitHubAccess(application: self)
        storage[GitHubAccessKey.self] = access

        return access
    }

    private struct GitHubAccessKey: StorageKey, LockKey {
        typealias Value = GitHubAccess
    }

    /// Mints and caches GitHub App installation tokens.
    ///
    /// Reached through `app.gitHubAccess`.
    public struct GitHubAccess: Sendable {

        internal let store: GitHubInstallationTokenStore

        private let configurationBox: NIOLockedValueBox<GitHubAccessConfiguration>

        internal init(application: Application) {
            self.store = GitHubInstallationTokenStore(application: application)
            self.configurationBox = NIOLockedValueBox(GitHubAccessConfiguration())
        }

        /// Tunables shared by every token request.
        ///
        /// Set this during application configuration, before the first token is requested.
        public var configuration: GitHubAccessConfiguration {
            get { configurationBox.withLockedValue { $0 } }
            nonmutating set { configurationBox.withLockedValue { $0 = newValue } }
        }

        /// Returns an installation token, reusing a cached one while it is still comfortably valid.
        ///
        /// - Parameter installationID: The GitHub App installation to mint a token for.
        public func installationToken(for installationID: Int64) async throws -> GitHubInstallationToken {
            try await store.token(for: installationID, configuration: configuration)
        }

        /// Mints a new installation token, ignoring — and replacing — any cached one.
        ///
        /// Useful when GitHub rejects a token the cache still considers valid.
        @discardableResult
        public func refreshInstallationToken(for installationID: Int64) async throws -> GitHubInstallationToken {
            try await store.refreshedToken(for: installationID, configuration: configuration)
        }

        /// Drops the cached token for a single installation.
        public func invalidateInstallationToken(for installationID: Int64) async {
            await store.removeToken(for: installationID)
        }

        /// Drops every cached token.
        public func invalidateInstallationTokens() async {
            await store.removeAllTokens()
        }

        /// Resolves the GitHub App configuration eagerly so that a misconfigured server fails at
        /// start-up rather than on the first token request.
        internal func prepare() async throws {
            try await store.prepare(configuration: configuration)
        }
    }
}
