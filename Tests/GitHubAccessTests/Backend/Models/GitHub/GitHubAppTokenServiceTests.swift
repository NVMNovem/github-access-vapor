//
//  GitHubAppTokenServiceTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 19/04/2026.
//

import Foundation
import Testing
import Vapor
@testable import GitHubAccessVapor

@Suite(.serialized)
struct GitHubAppTokenServiceTests {
    
    @Test("loads app ID and PEM contents from environment")
    func loadsConfigurationFromEnvironment() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let expectedPEM = """
        -----BEGIN PRIVATE KEY-----
        test-private-key
        -----END PRIVATE KEY-----
        """
        try expectedPEM.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        try await withEnvironment([
            "GITHUB_APP_ID": "42",
            "GITHUB_PRIVATE_KEY_PATH": tempFile.path
        ]) {
            let app = try await Application.make(.testing)
            defer {
                Task {
                    try? await app.asyncShutdown()
                }
            }
            
            let service = try GitHubAppTokenService(app: app)
            
            #expect(service.appID == "42")
            #expect(service.privateKeyPEM == expectedPEM)
        }
    }
    
    @Test("throws bad request when app ID is missing")
    func missingAppIDThrowsBadRequest() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "pem".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        try await withEnvironment([
            "GITHUB_APP_ID": nil,
            "GITHUB_PRIVATE_KEY_PATH": tempFile.path
        ]) {
            let app = try await Application.make(.testing)
            defer {
                Task {
                    try? await app.asyncShutdown()
                }
            }
            
            do {
                _ = try GitHubAppTokenService(app: app)
                Issue.record("Expected missing GITHUB_APP_ID to throw.")
            } catch let error as AbortError {
                #expect(error.status == .badRequest)
                #expect(error.reason == "Missing configuration value 'GITHUB_APP_ID'.")
            }
        }
    }
    
    @Test("throws bad request when private key path is missing")
    func missingPrivateKeyPathThrowsBadRequest() async throws {
        try await withEnvironment([
            "GITHUB_APP_ID": "42",
            "GITHUB_PRIVATE_KEY_PATH": nil
        ]) {
            let app = try await Application.make(.testing)
            defer {
                Task {
                    try? await app.asyncShutdown()
                }
            }
            
            do {
                _ = try GitHubAppTokenService(app: app)
                Issue.record("Expected missing GITHUB_PRIVATE_KEY_PATH to throw.")
            } catch let error as AbortError {
                #expect(error.status == .badRequest)
                #expect(error.reason == "Missing configuration value 'GITHUB_PRIVATE_KEY_PATH'.")
            }
        }
    }
    
    private func withEnvironment(
        _ overrides: [String: String?],
        operation: () async throws -> Void
    ) async throws {
        var previousValues: [String: String?] = [:]
        
        for key in overrides.keys {
            previousValues[key] = Environment.get(key)
        }
        
        for (key, value) in overrides {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
        
        defer {
            for (key, value) in previousValues {
                if let value {
                    setenv(key, value, 1)
                } else {
                    unsetenv(key)
                }
            }
        }
        
        try await operation()
    }
}
