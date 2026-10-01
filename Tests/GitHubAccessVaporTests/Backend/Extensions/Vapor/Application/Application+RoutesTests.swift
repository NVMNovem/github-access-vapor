//
//  Application+RoutesTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 01/10/2026.
//

import Foundation
import Testing

import Vapor
import VaporTesting

@testable import GitHubAccessVapor

@Suite("GitHub setup page")
struct GitHubSetupRouteTests {

    @Test("redirects a numeric installation to the app")
    func redirectsNumericInstallation() async throws {
        try await withApp { app in
            try await app.configureRoutes(project: "GitAssist", accent: "34C759")

            try await app.testing().test(.GET, "github/setup?installation_id=12345678") { response async in
                #expect(response.status == .ok)
                #expect(response.body.string.contains("gitassist://github/setup-complete?installation_id=12345678"))
            }
        }
    }

    @Test("rejects a missing installation")
    func rejectsMissingInstallation() async throws {
        try await withApp { app in
            try await app.configureRoutes(project: "GitAssist", accent: "34C759")

            try await app.testing().test(.GET, "github/setup") { response async in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test(
        "never reflects anything but a positive integer",
        arguments: [
            "%22%3B%3C%2Fscript%3E%3Cscript%3Ealert(1)%3C%2Fscript%3E",
            "1%22%3Ealert(1)",
            "1%3Cimg%20src%3Dx%3E",
            "abc",
            "0",
            "-5",
            "99999999999999999999"
        ]
    )
    func rejectsNonNumericInstallation(_ installationID: String) async throws {
        try await withApp { app in
            try await app.configureRoutes(project: "GitAssist", accent: "34C759")

            try await app.testing().test(.GET, "github/setup?installation_id=\(installationID)") { response async in
                #expect(response.status == .badRequest)
                #expect(!response.body.string.contains("<"))
                #expect(!response.body.string.contains("alert"))
            }
        }
    }

    @Test("mounts on its own, without GitHub App configuration or the token route")
    func mountsSetupPageAlone() async throws {
        try await withApp { app in
            try await app.configureSetupPage(project: "GitAssist", accent: "34C759", servesAssets: false)

            try await app.testing().test(.GET, "github/setup?installation_id=12345678") { response async in
                #expect(response.status == .ok)
                #expect(response.body.string.contains("gitassist://github/setup-complete?installation_id=12345678"))
            }
            try await app.testing().test(.POST, "github/token") { response async in
                #expect(response.status == .notFound)
            }
        }
    }
}
