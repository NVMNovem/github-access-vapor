//
//  GitHubEventDispatcherTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation
import Testing

import Vapor
import VaporTesting
import NIOCore

@testable import GitHubAccessVapor

@Suite("GitHubEventDispatcher")
struct GitHubEventDispatcherTests {

    private func makeRequest(on app: Application) -> Request {
        Request(application: app, on: app.eventLoopGroup.next())
    }

    private var delivery: GitHubWebhookDelivery {
        GitHubWebhookDelivery(
            id: "delivery-1",
            event: .release,
            payload: GitHubWebhookFixture.releasePublished
        )
    }

    @Test("runs every handler registered for an event")
    func runsEveryHandler() async throws {
        try await withApp { app in
            let recorder = GitHubEventRecorder()
            let dispatcher = app.gitHubEvents

            dispatcher.on(.release) { event, _ in await recorder.record(event) }
            dispatcher.on(.release) { event, _ in await recorder.record(event) }
            dispatcher.onAnyEvent { delivery, _ in await recorder.record(delivery) }

            await dispatcher.dispatch(delivery, on: makeRequest(on: app)).value

            let releases = await recorder.releases
            let deliveries = await recorder.deliveries
            #expect(releases.count == 2)
            #expect(deliveries.count == 1)
        }
    }

    @Test("keeps running handlers after one throws")
    func isolatesFailingHandlers() async throws {
        try await withApp { app in
            let recorder = GitHubEventRecorder()
            let dispatcher = app.gitHubEvents

            dispatcher.on(.release) { _, _ in
                throw Abort(.internalServerError, reason: "Handler blew up.")
            }
            dispatcher.on(.release) { event, _ in await recorder.record(event) }

            await dispatcher.dispatch(delivery, on: makeRequest(on: app)).value

            let releases = await recorder.releases
            #expect(releases.count == 1)
        }
    }

    @Test("skips a typed handler whose payload does not decode")
    func skipsUndecodablePayload() async throws {
        try await withApp { app in
            let recorder = GitHubEventRecorder()
            let dispatcher = app.gitHubEvents

            dispatcher.on(.release) { event, _ in await recorder.record(event) }
            dispatcher.onAnyEvent { delivery, _ in await recorder.record(delivery) }

            let malformed = GitHubWebhookDelivery(
                id: "delivery-2",
                event: .release,
                payload: Data(#"{"action":"published"}"#.utf8)
            )
            await dispatcher.dispatch(malformed, on: makeRequest(on: app)).value

            let releases = await recorder.releases
            let deliveries = await recorder.deliveries
            #expect(releases.isEmpty)
            #expect(deliveries.count == 1)
        }
    }

    @Test("leaves handlers for other events alone")
    func ignoresOtherEvents() async throws {
        try await withApp { app in
            let recorder = GitHubEventRecorder()
            let dispatcher = app.gitHubEvents

            dispatcher.on(event: "workflow_run") { delivery, _ in await recorder.record(delivery) }

            await dispatcher.dispatch(delivery, on: makeRequest(on: app)).value

            let deliveries = await recorder.deliveries
            #expect(deliveries.isEmpty)
        }
    }
}
