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

    private init(source: Source) {
        self.source = source
    }

    /// Reads the secret, throwing when an environment variable is unset or empty.
    public func resolve() throws -> String {
        switch source {
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
