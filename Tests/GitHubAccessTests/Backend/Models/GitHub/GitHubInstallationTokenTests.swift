//
//  GitHubInstallationTokenTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 19/04/2026.
//

import Foundation
import Testing
@testable import GitHubAccess

@Suite("GitHubInstallationToken")
struct GitHubInstallationTokenTests {

    @Test("decodes GitHub API response fields")
    func decodesInstallationTokenResponse() throws {
        let data = Data("""
        {
          "token": "ghs_example",
          "expires_at": "2026-04-19T10:15:30Z"
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let token = try decoder.decode(GitHubInstallationToken.self, from: data)

        #expect(token.token == "ghs_example")
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: TimeZone(secondsFromGMT: 0)!,
            from: token.expiresAt
        )
        #expect(components.year == 2026)
        #expect(components.month == 4)
        #expect(components.day == 19)
        #expect(components.hour == 10)
        #expect(components.minute == 15)
        #expect(components.second == 30)
    }

    @Test("fails decoding when expires_at is absent")
    func decodingFailsWhenExpiryIsMissing() {
        let data = Data("""
        {
          "token": "ghs_example"
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            _ = try decoder.decode(GitHubInstallationToken.self, from: data)
            Issue.record("Expected decode failure when expires_at is missing.")
        } catch {
            #expect(error is DecodingError)
        }
    }
}
