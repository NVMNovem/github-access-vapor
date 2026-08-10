//
//  Application+Webhooks.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

import Vapor

extension Application {

    /// The path webhooks are mounted on when none is given: `/github/webhook`.
    public static let defaultWebhookPath: [PathComponent] = ["github", "webhook"]

    /// Mounts the GitHub webhook endpoint.
    ///
    /// ```swift
    /// try app.configureWebhooks(secret: .environment("GITHUB_WEBHOOK_SECRET"),
    ///                           path: "github", "webhook")
    ///
    /// app.gitHubEvents.on(.release) { event, request in
    ///     // …
    /// }
    /// ```
    ///
    /// The route verifies `X-Hub-Signature-256` against the **raw** request body, deduplicates on
    /// `X-GitHub-Delivery`, hands the delivery to `app.gitHubEvents`, and answers immediately —
    /// GitHub times out at around ten seconds and records that as a failed delivery.
    ///
    /// Responses are `202 Accepted` for a delivery that was handed off, `200 OK` for one already
    /// seen, `400 Bad Request` for a missing header or body, and `401 Unauthorized` for a bad
    /// signature. Nothing reaches a handler unless the signature verified.
    ///
    /// - Parameters:
    ///   - secret: The signing secret configured on the GitHub webhook.
    ///   - path: Where to mount the endpoint. Defaults to `Application.defaultWebhookPath`.
    ///   - maxBodySize: The largest delivery accepted. GitHub caps payloads at 25 MB.
    ///   - recentDeliveryCapacity: How many recent delivery identifiers to remember for
    ///     deduplication.
    /// - Throws: When the secret cannot be resolved — a misconfigured server fails at start-up
    ///   rather than on the first delivery.
    @discardableResult
    public func configureWebhooks(
        secret: GitHubWebhookSecret,
        path: PathComponent...,
        maxBodySize: ByteCount = "25mb",
        recentDeliveryCapacity: Int = 512
    ) throws -> Route {
        try configureWebhooks(
            secret: secret,
            path: path,
            maxBodySize: maxBodySize,
            recentDeliveryCapacity: recentDeliveryCapacity
        )
    }

    /// Mounts the GitHub webhook endpoint on the given path.
    ///
    /// See `configureWebhooks(secret:path:maxBodySize:recentDeliveryCapacity:)`.
    @discardableResult
    public func configureWebhooks(
        secret: GitHubWebhookSecret,
        path: [PathComponent],
        maxBodySize: ByteCount = "25mb",
        recentDeliveryCapacity: Int = 512
    ) throws -> Route {
        let verifier = GitHubWebhookSignatureVerifier(secret: try secret.resolve())
        let deduplicator = GitHubDeliveryDeduplicator(capacity: recentDeliveryCapacity)
        let dispatcher = gitHubEvents
        let routePath = path.isEmpty ? Application.defaultWebhookPath : path

        // `.collect` is explicit so that `request.body.data` holds the complete, unmodified body by
        // the time the handler runs. The signature covers those exact bytes.
        return on(.POST, routePath, body: .collect(maxSize: maxBodySize)) { request async throws -> Response in
            guard let buffer = request.body.data else {
                throw Abort(.badRequest, reason: "Missing webhook request body.")
            }

            // Read the raw bytes before anything looks at the payload as JSON. Content decoding does
            // not round-trip byte-identically, and a re-encode invalidates the signature.
            let rawBody = Data(buffer: buffer)

            guard let signature = request.headers.first(
                name: GitHubWebhookSignatureVerifier.headerName
            ) else {
                throw Abort(
                    .badRequest,
                    reason: "Missing \(GitHubWebhookSignatureVerifier.headerName) header."
                )
            }

            guard let eventName = request.headers.first(name: GitHubWebhookHeader.event) else {
                throw Abort(.badRequest, reason: "Missing \(GitHubWebhookHeader.event) header.")
            }

            guard let deliveryID = request.headers.first(name: GitHubWebhookHeader.delivery) else {
                throw Abort(.badRequest, reason: "Missing \(GitHubWebhookHeader.delivery) header.")
            }

            guard verifier.isValidSignature(signature, body: rawBody) else {
                throw Abort(.unauthorized, reason: "Invalid webhook signature.")
            }

            guard await deduplicator.register(deliveryID) else {
                request.logger.debug("Ignoring redelivered GitHub webhook \(deliveryID).")
                return Response(status: .ok)
            }

            let delivery = GitHubWebhookDelivery(
                id: deliveryID,
                event: GitHubEventName(eventName),
                payload: rawBody
            )
            dispatcher.dispatch(delivery, on: request)

            return Response(status: .accepted)
        }
    }
}

/// The headers GitHub sends alongside a webhook delivery.
public enum GitHubWebhookHeader {

    /// Carries the event type.
    public static let event = "X-GitHub-Event"

    /// Carries a unique identifier for the delivery, stable across retries.
    public static let delivery = "X-GitHub-Delivery"

    /// Carries the HMAC-SHA256 signature of the raw body.
    public static let signature = GitHubWebhookSignatureVerifier.headerName
}
