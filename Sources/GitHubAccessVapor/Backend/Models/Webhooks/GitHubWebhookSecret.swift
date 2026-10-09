//
//  GitHubWebhookSecret.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Vapor

/// Where the webhook signing secret comes from.
///
/// ```swift
/// try app.configureWebhooks(secret: .environment("GITHUB_WEBHOOK_SECRET"))
/// ```
public struct GitHubWebhookSecret: Sendable {

    private enum Source: Sendable {
        case value(String)
        case environment(String)
        case provider(@Sendable () async throws -> String?)
    }

    /// The environment variable ``environment(_:)`` reads by default.
    public static let defaultEnvironmentKey = "GITHUB_WEBHOOK_SECRET"

    private let source: Source

    /// A secret held inline. Convenient in tests; prefer ``environment(_:)`` in production.
    public static func value(_ secret: String) -> GitHubWebhookSecret {
        GitHubWebhookSecret(source: .value(secret))
    }

    /// A secret read from an environment variable.
    ///
    /// - Parameter key: The variable to read. Defaults to `GITHUB_WEBHOOK_SECRET`.
    public static func environment(
        _ key: String = GitHubWebhookSecret.defaultEnvironmentKey
    ) -> GitHubWebhookSecret {
        GitHubWebhookSecret(source: .environment(key))
    }

    /// A secret asked for on every delivery, for hosts that learn it after start-up.
    ///
    /// The manifest flow is the case: GitHub generates the webhook secret when the App is created,
    /// which is after the server has started and mounted its routes (a route cannot be added once the
    /// server is running). Return `nil` while there is no secret yet; deliveries are then refused with
    /// `503` rather than accepted unverified. The closure runs for every delivery, so keep it cheap
    /// (read from memory, not from a vault).
    public static func provider(_ provide: @escaping @Sendable () async throws -> String?) -> GitHubWebhookSecret {
        GitHubWebhookSecret(source: .provider(provide))
    }

    /// Whether the secret can only be known per delivery, so ``resolve()`` is not meaningful.
    internal var isDeferred: Bool {
        if case .provider = source { return true }
        return false
    }

    /// The secret for one delivery: ``resolve()``, or the provider's current answer.
    ///
    /// - Throws: `Abort(.serviceUnavailable)` when a provider has no secret yet.
    internal func current() async throws -> String {
        guard case .provider(let provide) = source else { return try resolve() }
        guard let secret = try await provide(), !secret.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "The GitHub webhook secret is not configured yet.")
        }
        return secret
    }

    private init(source: Source) {
        self.source = source
    }

    /// Reads the secret, throwing when an environment variable is unset or empty.
    ///
    /// For a ``provider(_:)`` secret there is nothing to read synchronously, so this throws.
    public func resolve() throws -> String {
        switch source {
        case .provider:
            throw Abort(.badRequest, reason: "This GitHub webhook secret is provided per delivery.")
        case .value(let secret):
            guard !secret.isEmpty else {
                throw Abort(.badRequest, reason: "The GitHub webhook secret is empty.")
            }

            return secret
        case .environment(let key):
            return try GitHubConfiguration.value(named: key)
        }
    }
}
