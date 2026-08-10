//
//  Application+WebhooksTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation
import Testing

import Vapor
import VaporTesting
import NIOCore

import GitHubAccessVaporTesting
@testable import GitHubAccessVapor

@Suite("GitHub webhook route")
struct GitHubWebhookRouteTests {

    private let fixture = GitHubWebhookFixture.releasePublished
    private let secret = GitHubWebhookFixture.secret

    @Test("delivers a correctly signed release to its handler")
    func deliversSignedRelease() async throws {
        let recorder = GitHubEventRecorder()

        try await withApp { app in
            app.gitHubEvents.on(.release) { event, _ in
                await recorder.record(event)
            }
            try app.configureWebhooks(secret: .value(secret), path: "github", "webhook")

            try await app.testing().test(
                .POST,
                GitHubWebhookFixture.path,
                headers: GitHubWebhookFixture.headers(body: fixture),
                body: ByteBuffer(data: fixture)
            ) { response async in
                #expect(response.status == .accepted)
            }

            await recorder.waitForReleases(1)

            let releases = await recorder.releases
            #expect(releases.count == 1)
            #expect(releases.first?.action == .published)
            #expect(releases.first?.release.tagName == "1.4.0")
            #expect(releases.first?.repository.fullName == "octocat/hello-world")
            #expect(releases.first?.repository.isPrivate == true)
            #expect(releases.first?.installation?.id == 12345678)
            #expect(releases.first?.release.name == "Release café 1.4.0")
        }
    }

    @Test("verifies against the raw body, not a re-encoded one")
    func verifiesAgainstRawBody() async throws {
        // The fixture is not canonical JSON: decoding it and encoding the result yields different
        // bytes. If the route ever verified anything other than the bytes it received, one of the
        // two expectations below would flip.
        let canonicalised = try GitHubWebhookFixture.canonicalised(fixture)
        try #require(canonicalised != fixture)

        let signatureOverRawBody = GitHubWebhookSigner.sign(body: fixture, secret: secret)
        let recorder = GitHubEventRecorder()

        try await withApp { app in
            app.gitHubEvents.onAnyEvent { delivery, _ in
                await recorder.record(delivery)
            }
            try app.configureWebhooks(secret: .value(secret), path: "github", "webhook")

            // The exact bytes that were signed verify, and reach the handler untouched.
            try await app.testing().test(
                .POST,
                GitHubWebhookFixture.path,
                headers: GitHubWebhookFixture.headers(body: fixture, signature: signatureOverRawBody),
                body: ByteBuffer(data: fixture)
            ) { response async in
                #expect(response.status == .accepted)
            }

            await recorder.waitForDeliveries(1)
            let delivered = await recorder.deliveries.first
            #expect(delivered?.payload == fixture)

            // A semantically identical body, signed for the original bytes, does not verify.
            try await app.testing().test(
                .POST,
                GitHubWebhookFixture.path,
                headers: GitHubWebhookFixture.headers(
                    body: canonicalised,
                    signature: signatureOverRawBody
                ),
                body: ByteBuffer(data: canonicalised)
            ) { response async in
                #expect(response.status == .unauthorized)
            }

            await recorder.settle()
            let deliveries = await recorder.deliveries
            #expect(deliveries.count == 1)
        }
    }

    @Test("rejects a body that was tampered with after signing")
    func rejectsTamperedBody() async throws {
        let signature = GitHubWebhookSigner.sign(body: fixture, secret: secret)
        let tampered = Data(
            String(decoding: fixture, as: UTF8.self)
                .replacingOccurrences(of: "1.4.0", with: "9.9.9")
                .utf8
        )
        let recorder = GitHubEventRecorder()

        try await withApp { app in
            app.gitHubEvents.onAnyEvent { delivery, _ in
                await recorder.record(delivery)
            }
            try app.configureWebhooks(secret: .value(secret), path: "github", "webhook")

            try await app.testing().test(
                .POST,
                GitHubWebhookFixture.path,
                headers: GitHubWebhookFixture.headers(body: tampered, signature: signature),
                body: ByteBuffer(data: tampered)
            ) { response async in
                #expect(response.status == .unauthorized)
            }

            await recorder.settle()
            let deliveries = await recorder.deliveries
            #expect(deliveries.isEmpty)
        }
    }

    @Test("rejects a body signed with the wrong secret")
    func rejectsWrongSecret() async throws {
        let recorder = GitHubEventRecorder()

        try await withApp { app in
            app.gitHubEvents.onAnyEvent { delivery, _ in
                await recorder.record(delivery)
            }
            try app.configureWebhooks(secret: .value(secret), path: "github", "webhook")

            try await app.testing().test(
                .POST,
                GitHubWebhookFixture.path,
                headers: GitHubWebhookFixture.headers(body: fixture, secret: "not-the-secret"),
                body: ByteBuffer(data: fixture)
            ) { response async in
                #expect(response.status == .unauthorized)
            }

            await recorder.settle()
            let deliveries = await recorder.deliveries
            #expect(deliveries.isEmpty)
        }
    }

    @Test("rejects a delivery with no signature header at all")
    func rejectsMissingSignatureHeader() async throws {
        let recorder = GitHubEventRecorder()

        try await withApp { app in
            app.gitHubEvents.onAnyEvent { delivery, _ in
                await recorder.record(delivery)
            }
            try app.configureWebhooks(secret: .value(secret), path: "github", "webhook")

            var headers = HTTPHeaders()
            headers.contentType = .json
            headers.add(name: "X-GitHub-Event", value: "release")
            headers.add(name: "X-GitHub-Delivery", value: UUID().uuidString)

            try await app.testing().test(
                .POST,
                GitHubWebhookFixture.path,
                headers: headers,
                body: ByteBuffer(data: fixture)
            ) { response async in
                #expect(response.status == .badRequest)
            }

            await recorder.settle()
            let deliveries = await recorder.deliveries
            #expect(deliveries.isEmpty)
        }
    }

    @Test("rejects a delivery with a missing event or delivery header", arguments: [
        "X-GitHub-Event",
        "X-GitHub-Delivery"
    ])
    func rejectsMissingHeader(named missing: String) async throws {
        try await withApp { app in
            try app.configureWebhooks(secret: .value(secret), path: "github", "webhook")

            var headers = GitHubWebhookFixture.headers(body: fixture)
            headers.remove(name: missing)

            try await app.testing().test(
                .POST,
                GitHubWebhookFixture.path,
                headers: headers,
                body: ByteBuffer(data: fixture)
            ) { response async in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("fires the handler once for a redelivered X-GitHub-Delivery")
    func deduplicatesRedeliveries() async throws {
        let recorder = GitHubEventRecorder()
        let deliveryID = "9d0e2a4c-0000-4000-8000-000000000001"
        let redeliveredID = "9d0e2a4c-0000-4000-8000-000000000002"

        try await withApp { app in
            app.gitHubEvents.onAnyEvent { delivery, _ in
                await recorder.record(delivery)
            }
            try app.configureWebhooks(secret: .value(secret), path: "github", "webhook")

            let tester = try app.testing()
            let headers = GitHubWebhookFixture.headers(body: fixture, deliveryID: deliveryID)

            try await tester.test(
                .POST,
                GitHubWebhookFixture.path,
                headers: headers,
                body: ByteBuffer(data: fixture)
            ) { response async in
                #expect(response.status == .accepted)
            }

            await recorder.waitForDeliveries(1)

            // GitHub retries the same delivery.
            try await tester.test(
                .POST,
                GitHubWebhookFixture.path,
                headers: headers,
                body: ByteBuffer(data: fixture)
            ) { response async in
                #expect(response.status == .ok)
            }

            // A genuinely new delivery still gets through, which is what makes the assertion below
            // meaningful rather than a race with a handler that has not run yet.
            try await tester.test(
                .POST,
                GitHubWebhookFixture.path,
                headers: GitHubWebhookFixture.headers(body: fixture, deliveryID: redeliveredID),
                body: ByteBuffer(data: fixture)
            ) { response async in
                #expect(response.status == .accepted)
            }

            await recorder.waitForDeliveries(2)
            await recorder.settle()

            let deliveries = await recorder.deliveries
            #expect(deliveries.map(\.id) == [deliveryID, redeliveredID])
        }
    }

    @Test("mounts on github/webhook when no path is given")
    func mountsDefaultPath() async throws {
        let recorder = GitHubEventRecorder()

        try await withApp { app in
            app.gitHubEvents.onAnyEvent { delivery, _ in
                await recorder.record(delivery)
            }
            try app.configureWebhooks(secret: .value(secret))

            try await app.testing().test(
                .POST,
                GitHubWebhookFixture.path,
                headers: GitHubWebhookFixture.headers(body: fixture),
                body: ByteBuffer(data: fixture)
            ) { response async in
                #expect(response.status == .accepted)
            }

            await recorder.waitForDeliveries(1)
            let deliveries = await recorder.deliveries
            #expect(deliveries.count == 1)
        }
    }

    @Test("routes an unmodelled event to its raw handler")
    func routesUnmodelledEvent() async throws {
        let recorder = GitHubEventRecorder()

        try await withApp { app in
            app.gitHubEvents.on(event: "workflow_run") { delivery, _ in
                await recorder.record(delivery)
            }
            app.gitHubEvents.on(.release) { event, _ in
                await recorder.record(event)
            }
            try app.configureWebhooks(secret: .value(secret), path: "github", "webhook")

            let payload = Data(#"{"action":"completed"}"#.utf8)

            try await app.testing().test(
                .POST,
                GitHubWebhookFixture.path,
                headers: GitHubWebhookFixture.headers(body: payload, event: "workflow_run"),
                body: ByteBuffer(data: payload)
            ) { response async in
                #expect(response.status == .accepted)
            }

            await recorder.waitForDeliveries(1)
            await recorder.settle()

            let deliveries = await recorder.deliveries
            let releases = await recorder.releases
            #expect(deliveries.count == 1)
            #expect(deliveries.first?.event == GitHubEventName("workflow_run"))
            #expect(releases.isEmpty)
        }
    }

    @Test("throws when the secret cannot be resolved")
    func throwsOnMissingSecret() async throws {
        try await withApp { app in
            do {
                try app.configureWebhooks(secret: .environment("GITHUB_WEBHOOK_SECRET_THAT_IS_UNSET"))
                Issue.record("Expected an unresolvable secret to throw.")
            } catch let error as AbortError {
                #expect(error.status == .badRequest)
            }
        }
    }
}
