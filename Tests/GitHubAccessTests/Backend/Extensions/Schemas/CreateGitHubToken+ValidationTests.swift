//
//  CreateGitHubToken+ValidationTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 19/04/2026.
//

import Testing
@testable import GitHubAccessVapor

@Suite("CreateGitHubToken Validation")
struct CreateGitHubTokenValidationTests {

    @Test("returns the installation ID unchanged")
    func returnsInstallationID() throws {
        let payload = Components.Schemas.CreateGitHubToken(installationId: 987_654_321)

        let installationID = try payload.validated(\.installationId)

        #expect(installationID == 987_654_321)
    }

    @Test("supports zero when the schema provides zero")
    func preservesZeroValue() throws {
        let payload = Components.Schemas.CreateGitHubToken(installationId: 0)

        let installationID = try payload.validated(\.installationId)

        #expect(installationID == 0)
    }
}
