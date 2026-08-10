//
//  GitHubEventDispatcher.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

import Vapor
import NIOConcurrencyHelpers

/// The registry of webhook handlers, reached through `app.gitHubEvents`.
///
/// ```swift
/// app.gitHubEvents.on(.release) { event, request in
///     guard event.action == .published else { return }
///     // …
/// }
/// ```
///
/// Handlers run *after* the webhook route has answered GitHub, so a slow handler cannot turn a
/// delivery into a timeout. They may take as long as they need.
public final class GitHubEventDispatcher: Sendable {

    /// A handler that receives the raw, verified delivery.
    public typealias DeliveryHandler = @Sendable (GitHubWebhookDelivery, Request) async throws -> Void

    private struct Handlers: Sendable {
        var named: [GitHubEventName: [DeliveryHandler]] = [:]
        var any: [DeliveryHandler] = []
    }

    private let handlers = NIOLockedValueBox(Handlers())

    internal init() {}

    /// Registers a handler for a typed event.
    ///
    /// The payload is decoded from the delivery before the handler runs; a payload that fails to
    /// decode is logged and the handler is skipped.
    public func on<Event: GitHubWebhookEvent>(
        _ event: GitHubEventKey<Event>,
        use handler: @escaping @Sendable (Event, Request) async throws -> Void
    ) {
        on(event: event.name) { delivery, request in
            try await handler(delivery.decode(Event.self), request)
        }
    }

    /// Registers a handler for an event this package does not model, by raw name.
    ///
    /// ```swift
    /// app.gitHubEvents.on(event: "workflow_run") { delivery, request in
    ///     let payload = try delivery.decode(MyWorkflowRun.self)
    /// }
    /// ```
    public func on(event name: GitHubEventName, use handler: @escaping DeliveryHandler) {
        handlers.withLockedValue { $0.named[name, default: []].append(handler) }
    }

    /// Registers a handler that receives every verified delivery, whatever its event.
    public func onAnyEvent(use handler: @escaping DeliveryHandler) {
        handlers.withLockedValue { $0.any.append(handler) }
    }

    /// Removes every registered handler.
    public func removeAllHandlers() {
        handlers.withLockedValue { $0 = Handlers() }
    }

    /// Hands the delivery off to its handlers without waiting for them.
    ///
    /// GitHub times out at around ten seconds and treats that as a failed delivery, so the route
    /// answers first and the work happens here.
    @discardableResult
    internal func dispatch(_ delivery: GitHubWebhookDelivery, on request: Request) -> Task<Void, Never> {
        let matching = handlers.withLockedValue { handlers in
            handlers.any + (handlers.named[delivery.event] ?? [])
        }

        return Task {
            for handler in matching {
                do {
                    try await handler(delivery, request)
                } catch {
                    request.logger.error(
                        "GitHub webhook handler failed: \(String(reflecting: error))",
                        metadata: [
                            "github-event": .string(delivery.event.rawValue),
                            "github-delivery": .string(delivery.id)
                        ]
                    )
                }
            }
        }
    }
}
