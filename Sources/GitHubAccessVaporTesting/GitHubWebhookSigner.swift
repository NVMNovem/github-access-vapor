//
//  GitHubWebhookSigner.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

import Crypto

/// Signs webhook fixtures the way GitHub signs real deliveries, so downstream packages can test
/// their handlers without reimplementing HMAC.
///
/// ```swift
/// import GitHubAccessVaporTesting
///
/// let signature = GitHubWebhookSigner.sign(body: fixture, secret: "test-secret")
/// ```
///
/// The returned value is the complete `X-Hub-Signature-256` header value, prefix included.
///
/// Sign the exact bytes you send. Encoding a fixture, signing the encoded form, and then sending a
/// re-encoded copy produces a signature that will not verify — which is the same trap real
/// deliveries fall into.
public enum GitHubWebhookSigner {

    /// The header the signature belongs in.
    public static let headerName = "X-Hub-Signature-256"

    /// The prefix the header value carries before the hex digest.
    public static let signaturePrefix = "sha256="

    /// Returns the `X-Hub-Signature-256` value for `body` under `secret`.
    public static func sign(body: some DataProtocol, secret: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(
            for: body,
            using: SymmetricKey(data: Array(secret.utf8))
        )

        return signaturePrefix + code.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the `X-Hub-Signature-256` value for the UTF-8 bytes of `body` under `secret`.
    public static func sign(body: String, secret: String) -> String {
        sign(body: Data(body.utf8), secret: secret)
    }

    /// The headers a signed delivery needs, ready to attach to a test request.
    ///
    /// - Parameters:
    ///   - body: The exact bytes that will be sent.
    ///   - secret: The webhook signing secret.
    ///   - event: The `X-GitHub-Event` value.
    ///   - deliveryID: The `X-GitHub-Delivery` value. A fresh UUID by default; reuse one to
    ///     simulate a redelivery.
    public static func headers(
        body: some DataProtocol,
        secret: String,
        event: String,
        deliveryID: String = UUID().uuidString
    ) -> [String: String] {
        [
            headerName: sign(body: body, secret: secret),
            "X-GitHub-Event": event,
            "X-GitHub-Delivery": deliveryID
        ]
    }
}
