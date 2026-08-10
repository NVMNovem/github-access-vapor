//
//  GitHubWebhookSignatureVerifier.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

import Crypto

/// Verifies the `X-Hub-Signature-256` header GitHub signs webhook deliveries with.
///
/// The signature covers the **raw request body**. Decoding the body and re-encoding it produces
/// different bytes — different key order, different whitespace, different number formatting — and
/// any such round trip invalidates the signature. Always verify against the bytes as received.
///
/// ```swift
/// let verifier = GitHubWebhookSignatureVerifier(secret: "s3cret")
/// let isValid = verifier.isValidSignature(header, body: request.body.data.map(Data.init(buffer:)) ?? Data())
/// ```
///
/// Uses swift-crypto, not CryptoKit, so it works on Linux; comparison is constant time.
public struct GitHubWebhookSignatureVerifier: Sendable {

    /// The header GitHub sends the signature in.
    public static let headerName = "X-Hub-Signature-256"

    /// The prefix the header value carries before the hex digest.
    public static let signaturePrefix = "sha256="

    private let secret: [UInt8]

    public init(secret: String) {
        self.secret = Array(secret.utf8)
    }

    /// Whether `header` is a valid `X-Hub-Signature-256` for `body`.
    ///
    /// - Parameters:
    ///   - header: The raw header value, including its `sha256=` prefix.
    ///   - body: The request body exactly as received.
    public func isValidSignature(_ header: String, body: some DataProtocol) -> Bool {
        guard header.hasPrefix(Self.signaturePrefix) else { return false }

        let hex = String(header.dropFirst(Self.signaturePrefix.count))
        guard let expected = Self.hexDecoded(hex) else { return false }

        return HMAC<SHA256>.isValidAuthenticationCode(
            expected,
            authenticating: body,
            using: SymmetricKey(data: secret)
        )
    }

    /// Whether `header` is a valid `X-Hub-Signature-256` for `body`, under `secret`.
    public static func isValidSignature(
        _ header: String,
        body: some DataProtocol,
        secret: String
    ) -> Bool {
        GitHubWebhookSignatureVerifier(secret: secret).isValidSignature(header, body: body)
    }

    private static func hexDecoded(_ string: String) -> [UInt8]? {
        let characters = Array(string.utf8)
        guard !characters.isEmpty, characters.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(characters.count / 2)

        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let high = nibble(characters[index]),
                  let low = nibble(characters[index + 1]) else { return nil }

            bytes.append(high << 4 | low)
        }

        return bytes
    }

    private static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): character - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
