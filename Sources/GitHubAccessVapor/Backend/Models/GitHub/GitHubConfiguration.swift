//
//  GitHubConfiguration.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Vapor

/// Reads the environment values this package is configured with.
internal enum GitHubConfiguration {

    internal static let appIDKey = "GITHUB_APP_ID"
    internal static let privateKeyPathKey = "GITHUB_PRIVATE_KEY_PATH"
    internal static let privateKeyKey = "GITHUB_PRIVATE_KEY"

    /// Returns the value of `key`, or `nil` when it is unset or empty.
    internal static func optionalValue(named key: String) -> String? {
        guard let value = Environment.get(key), !value.isEmpty else { return nil }

        return value
    }

    /// Returns the value of `key`, throwing when it is unset or empty.
    internal static func value(named key: String) throws -> String {
        guard let value = optionalValue(named: key) else {
            throw missingValue(named: key)
        }

        return value
    }

    internal static func missingValue(named key: String) -> Abort {
        Abort(.badRequest, reason: "Missing configuration value '\(key)'.")
    }
}
