//
//  GitHubAccessController+ErrorTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 19/04/2026.
//

import Testing
@testable import GitHubAccess

@Suite("GitHubAccessController Error")
struct GitHubAccessControllerErrorTests {

    @Test("maps invalid installation ID to a stable public message")
    func invalidInstallationIDMessage() {
        #expect(
            GitHubAccessController.Error.Code.invalidInstallationId.message
            == "The installation id is invalid."
        )
    }

    @Test("creates a bad-request error with the matching code and message")
    func badRequestFactoryBuildsExpectedError() {
        let error = GitHubAccessController.Error.badRequest(.invalidInstallationId)

        #expect(error.status == .badRequest)
        #expect(error.code == .invalidInstallationId)
        #expect(error.message == "The installation id is invalid.")
    }
}
