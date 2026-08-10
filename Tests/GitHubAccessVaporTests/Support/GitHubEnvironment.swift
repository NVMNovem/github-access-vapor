//
//  GitHubEnvironment.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

import Vapor

/// Runs a test with process environment overrides in place.
///
/// The process environment is global, and Swift Testing runs suites in parallel, so every override
/// is taken under a shared lock. Tests that touch `GITHUB_*` variables must go through here.
internal enum GitHubEnvironment {

    internal static func with(
        _ overrides: [String: String?],
        operation: () async throws -> Void
    ) async throws {
        await lock.acquire()
        defer { lock.release() }

        var previousValues: [String: String?] = [:]
        for key in overrides.keys {
            previousValues[key] = Environment.get(key)
        }

        apply(overrides)
        defer { apply(previousValues) }

        try await operation()
    }

    /// Writes a placeholder PEM to a temporary file.
    ///
    /// Nothing under test parses it — the key is only read at token-signing time, which these tests
    /// never reach.
    internal static func temporaryPrivateKeyFile(
        contents: String = GitHubEnvironment.placeholderPEM
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)

        return url
    }

    internal static let placeholderPEM = """
    -----BEGIN PRIVATE KEY-----
    test-private-key
    -----END PRIVATE KEY-----
    """

    private static let lock = AsyncLock()

    private static func apply(_ values: [String: String?]) {
        for (key, value) in values {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }
}

/// A mutual exclusion lock that can be held across suspension points.
internal actor AsyncLock {

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    internal func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    internal nonisolated func release() {
        Task { await releaseNow() }
    }

    private func releaseNow() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }

        waiters.removeFirst().resume()
    }
}
