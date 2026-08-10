//
//  GitHubWebhookEvent.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

/// A decodable webhook payload tied to the `X-GitHub-Event` value that carries it.
///
/// Adding an event type is additive: declare the payload, conform it to this protocol, and add a
/// matching ``GitHubEventKey`` so it can be registered as `on(.myEvent)`.
public protocol GitHubWebhookEvent: Decodable, Sendable {

    /// The `X-GitHub-Event` value this payload belongs to.
    static var eventName: GitHubEventName { get }
}

/// A typed handle on an event, pairing its name with the payload it decodes to.
///
/// ```swift
/// app.gitHubEvents.on(.release) { event, request in
///     print(event.release.tagName)
/// }
/// ```
public struct GitHubEventKey<Event: GitHubWebhookEvent>: Sendable {

    public let name: GitHubEventName

    public init() {
        self.name = Event.eventName
    }
}
