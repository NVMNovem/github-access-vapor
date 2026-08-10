//
//  READMEExampleTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//
//  The examples in README.md, verbatim, so that they keep compiling.
//

import Foundation
import Testing

import Vapor
import VaporTesting

import GitHubAccessVaporTesting
import GitHubAccessVapor

@Suite("README examples")
struct READMEExampleTests {

    // MARK: - Basic usage

    func configure(_ app: Application) async throws {
        try await app.configureAccessServer(project: "MyApp", accent: "34C759")
    }

    // MARK: - Installation tokens, in-process

    func cloneURL(
        for repository: String,
        installationID: Int64,
        on app: Application
    ) async throws -> String {
        let token = try await app.gitHubAccess.installationToken(for: installationID)

        return "https://x-access-token:\(token.token)@github.com/\(repository).git"
    }

    func configureCaching(_ app: Application, installationID: Int64) async throws {
        app.gitHubAccess.configuration.userAgent = "MyApp"
        app.gitHubAccess.configuration.refreshLeeway = 10 * 60

        // If GitHub rejects a token the cache still considers valid:
        let fresh = try await app.gitHubAccess.refreshInstallationToken(for: installationID)
        _ = fresh
    }

    // MARK: - Webhooks

    func configureWebhooks(_ app: Application) async throws {
        try app.configureWebhooks(secret: .environment("GITHUB_WEBHOOK_SECRET"),
                                  path: "github", "webhook")

        app.gitHubEvents.on(.release) { event, request in
            guard event.action == .published else { return }

            request.logger.info("\(event.repository.fullName) released \(event.release.tagName)")

            if let installation = event.installation {
                let token = try await request.application.gitHubAccess.installationToken(for: installation.id)
                // …clone or call the GitHub API with `token.token`.
                _ = token
            }
        }
    }

    struct MyWorkflowRun: Decodable {
        let action: String
    }

    func configureUnmodelledEvent(_ app: Application) {
        app.gitHubEvents.on(event: "workflow_run") { delivery, request in
            let payload = try delivery.decode(MyWorkflowRun.self)
            _ = payload
        }
    }

    // MARK: - Testing

    @Test func rejectsATamperedBody() {
        let body = Data(#"{"action":"published"}"#.utf8)
        let signature = GitHubWebhookSigner.sign(body: body, secret: "test-secret")
        let verifier = GitHubWebhookSignatureVerifier(secret: "test-secret")

        #expect(verifier.isValidSignature(signature, body: body))
        #expect(verifier.isValidSignature(signature, body: Data(#"{"action":"deleted"}"#.utf8)) == false)
    }

    // MARK: - The examples above, exercised end to end

    @Test("the in-process token example runs without configureAccessServer")
    func cloneURLExample() async throws {
        try await GitHubEnvironment.with([
            "GITHUB_APP_ID": nil,
            "GITHUB_PRIVATE_KEY_PATH": nil,
            "GITHUB_PRIVATE_KEY": nil
        ]) {
            try await withApp { app in
                // No `configureAccessServer`, no routes: the example reaches GitHub App
                // configuration on its own, and says which variable is missing.
                do {
                    _ = try await cloneURL(for: "octocat/hello-world", installationID: 1, on: app)
                    Issue.record("Expected the missing GitHub App configuration to throw.")
                } catch let error as AbortError {
                    #expect(error.reason == "Missing configuration value 'GITHUB_APP_ID'.")
                }
            }
        }
    }

    @Test("the webhook example receives a signed release")
    func webhookExample() async throws {
        try await GitHubEnvironment.with(["GITHUB_WEBHOOK_SECRET": GitHubWebhookFixture.secret]) {
            try await withApp { app in
                try await configureWebhooks(app)
                configureUnmodelledEvent(app)

                try await app.testing().test(
                    .POST,
                    GitHubWebhookFixture.path,
                    headers: GitHubWebhookFixture.headers(body: GitHubWebhookFixture.releasePublished),
                    body: ByteBuffer(data: GitHubWebhookFixture.releasePublished)
                ) { response async in
                    #expect(response.status == .accepted)
                }
            }
        }
    }
}
