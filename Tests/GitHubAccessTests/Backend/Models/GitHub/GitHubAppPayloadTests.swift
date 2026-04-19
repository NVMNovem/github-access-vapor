//
//  GitHubAppPayloadTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 19/04/2026.
//

import Foundation
import JWTKit
import Testing
@testable import GitHubAccess

@Suite("GitHubAppPayload")
struct GitHubAppPayloadTests {

    @Test("initializes issuer and token timestamps relative to now")
    func initializesRelativeClaims() {
        let now = Date(timeIntervalSince1970: 1_713_456_789)

        let payload = GitHubAppPayload(appID: "12345", now: now)

        #expect(payload.iss == "12345")
        #expect(payload.iat == 1_713_456_729)
        #expect(payload.exp == 1_713_457_329)
    }

    @Test("sets expiration after issued-at time")
    func expirationIsAfterIssuedAt() {
        let payload = GitHubAppPayload(appID: "app-id", now: .now)

        #expect(payload.exp > payload.iat)
        #expect(payload.exp - payload.iat == 10 * 60)
    }
}
