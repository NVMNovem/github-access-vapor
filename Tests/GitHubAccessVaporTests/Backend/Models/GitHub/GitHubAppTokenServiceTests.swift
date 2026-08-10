//
//  GitHubAppTokenServiceTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 19/04/2026.
//

import Foundation
import Testing

import Vapor
import VaporTesting

@testable import GitHubAccessVapor

@Suite(.serialized)
struct GitHubAppTokenServiceTests {

    @Test("loads app ID and PEM contents from environment")
    func loadsConfigurationFromEnvironment() async throws {
        let keyFile = try GitHubEnvironment.temporaryPrivateKeyFile()
        defer { try? FileManager.default.removeItem(at: keyFile) }

        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": "42",
            "GITHUB_PRIVATE_KEY_PATH": keyFile.path,
            "GITHUB_PRIVATE_KEY": nil
        ]) {
            try await withApp { app in
                let service = try GitHubAppTokenService(app: app)

                #expect(service.appID == "42")
                #expect(service.privateKeyPEM == GitHubEnvironment.placeholderPEM)
                #expect(service.userAgent == "GitSyncAccessServer")
            }
        }
    }

    @Test("reads the PEM inline from GITHUB_PRIVATE_KEY when no path is set")
    func readsInlinePrivateKey() async throws {
        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": "42",
            "GITHUB_PRIVATE_KEY_PATH": nil,
            "GITHUB_PRIVATE_KEY": GitHubEnvironment.placeholderPEM
        ]) {
            try await withApp { app in
                let service = try GitHubAppTokenService(app: app)

                #expect(service.privateKeyPEM == GitHubEnvironment.placeholderPEM)
            }
        }
    }

    @Test("restores escaped newlines in a single-line inline PEM")
    func restoresEscapedNewlinesInInlinePrivateKey() async throws {
        let escaped = GitHubEnvironment.placeholderPEM.replacingOccurrences(of: "\n", with: "\\n")

        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": "42",
            "GITHUB_PRIVATE_KEY_PATH": nil,
            "GITHUB_PRIVATE_KEY": escaped
        ]) {
            try await withApp { app in
                let service = try GitHubAppTokenService(app: app)

                #expect(service.privateKeyPEM == GitHubEnvironment.placeholderPEM)
            }
        }
    }

    @Test("prefers the private key path over the inline PEM")
    func prefersPathOverInlinePrivateKey() async throws {
        let keyFile = try GitHubEnvironment.temporaryPrivateKeyFile(contents: "from-file")
        defer { try? FileManager.default.removeItem(at: keyFile) }

        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": "42",
            "GITHUB_PRIVATE_KEY_PATH": keyFile.path,
            "GITHUB_PRIVATE_KEY": "from-environment"
        ]) {
            try await withApp { app in
                let service = try GitHubAppTokenService(app: app)

                #expect(service.privateKeyPEM == "from-file")
            }
        }
    }

    @Test("uses the given User-Agent")
    func usesGivenUserAgent() async throws {
        let keyFile = try GitHubEnvironment.temporaryPrivateKeyFile()
        defer { try? FileManager.default.removeItem(at: keyFile) }

        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": "42",
            "GITHUB_PRIVATE_KEY_PATH": keyFile.path,
            "GITHUB_PRIVATE_KEY": nil
        ]) {
            try await withApp { app in
                let service = try GitHubAppTokenService(app: app, userAgent: "MyApp")

                #expect(service.userAgent == "MyApp")
            }
        }
    }

    @Test("throws bad request when app ID is missing")
    func missingAppIDThrowsBadRequest() async throws {
        let keyFile = try GitHubEnvironment.temporaryPrivateKeyFile()
        defer { try? FileManager.default.removeItem(at: keyFile) }

        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": nil,
            "GITHUB_PRIVATE_KEY_PATH": keyFile.path,
            "GITHUB_PRIVATE_KEY": nil
        ]) {
            try await withApp { app in
                do {
                    _ = try GitHubAppTokenService(app: app)
                    Issue.record("Expected missing GITHUB_APP_ID to throw.")
                } catch let error as AbortError {
                    #expect(error.status == .badRequest)
                    #expect(error.reason == "Missing configuration value 'GITHUB_APP_ID'.")
                }
            }
        }
    }

    @Test("throws bad request when neither private key source is set")
    func missingPrivateKeyThrowsBadRequest() async throws {
        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": "42",
            "GITHUB_PRIVATE_KEY_PATH": nil,
            "GITHUB_PRIVATE_KEY": nil
        ]) {
            try await withApp { app in
                do {
                    _ = try GitHubAppTokenService(app: app)
                    Issue.record("Expected a missing private key to throw.")
                } catch let error as AbortError {
                    #expect(error.status == .badRequest)
                    #expect(
                        error.reason
                        == "Missing configuration value 'GITHUB_PRIVATE_KEY_PATH' or 'GITHUB_PRIVATE_KEY'."
                    )
                }
            }
        }
    }
}
