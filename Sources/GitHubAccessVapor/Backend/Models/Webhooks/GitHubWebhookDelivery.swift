//
//  GitHubWebhookDelivery.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

/// A single, signature-verified webhook delivery.
///
/// The envelope carries the payload as the raw bytes GitHub sent, not as a re-encoded object.
/// Those bytes are what the signature was computed over, and re-encoding JSON does not round-trip
/// byte-identically.
public struct GitHubWebhookDelivery: Sendable {

    /// The `X-GitHub-Delivery` value: a unique identifier for this delivery attempt's payload.
    ///
    /// GitHub reuses it across retries of the same delivery, which is what makes it usable for
    /// deduplication.
    public let id: String

    /// The `X-GitHub-Event` value.
    public let event: GitHubEventName

    /// The verified request body, exactly as received.
    public let payload: Data

    public init(id: String, event: GitHubEventName, payload: Data) {
        self.id = id
        self.event = event
        self.payload = payload
    }

    /// The default decoder: ISO 8601 dates, and no key conversion — payload types declare their own
    /// `CodingKeys`.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return decoder
    }

    /// Decodes ``payload`` into a type of your choosing.
    ///
    /// Useful for event types this package does not model yet:
    ///
    /// ```swift
    /// app.gitHubEvents.on(event: "workflow_run") { delivery, request in
    ///     let payload = try delivery.decode(MyWorkflowRun.self)
    /// }
    /// ```
    public func decode<Payload: Decodable>(
        _ type: Payload.Type = Payload.self,
        using decoder: JSONDecoder = GitHubWebhookDelivery.makeDecoder()
    ) throws -> Payload {
        try decoder.decode(Payload.self, from: payload)
    }
}
