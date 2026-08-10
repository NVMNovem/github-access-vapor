//
//  GitHubWebhookSignatureVerifierTests.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation
import Testing

import GitHubAccessVaporTesting
@testable import GitHubAccessVapor

@Suite("GitHubWebhookSignatureVerifier")
struct GitHubWebhookSignatureVerifierTests {

    private let secret = "test-secret"
    private let body = Data(#"{"action":"published","release":{"tag_name":"1.2.3"}}"#.utf8)

    @Test("accepts a correctly signed body")
    func acceptsCorrectSignature() {
        let signature = GitHubWebhookSigner.sign(body: body, secret: secret)
        let verifier = GitHubWebhookSignatureVerifier(secret: secret)

        #expect(verifier.isValidSignature(signature, body: body))
    }

    @Test("rejects a body that was tampered with after signing")
    func rejectsTamperedBody() {
        let signature = GitHubWebhookSigner.sign(body: body, secret: secret)
        let tampered = Data(#"{"action":"published","release":{"tag_name":"9.9.9"}}"#.utf8)
        let verifier = GitHubWebhookSignatureVerifier(secret: secret)

        #expect(verifier.isValidSignature(signature, body: tampered) == false)
    }

    @Test("rejects a signature made with a different secret")
    func rejectsWrongSecret() {
        let signature = GitHubWebhookSigner.sign(body: body, secret: "another-secret")
        let verifier = GitHubWebhookSignatureVerifier(secret: secret)

        #expect(verifier.isValidSignature(signature, body: body) == false)
    }

    @Test("rejects a signature that changes by a single byte")
    func rejectsAlmostCorrectSignature() {
        let signature = GitHubWebhookSigner.sign(body: body, secret: secret)
        let flipped = signature.dropLast() + (signature.hasSuffix("a") ? "b" : "a")
        let verifier = GitHubWebhookSignatureVerifier(secret: secret)

        #expect(verifier.isValidSignature(String(flipped), body: body) == false)
    }

    @Test("rejects malformed header values", arguments: [
        "",
        "sha1=abcdef",
        "abcdef",
        "sha256=",
        "sha256=nothexatall",
        "sha256=abc"
    ])
    func rejectsMalformedHeaders(header: String) {
        let verifier = GitHubWebhookSignatureVerifier(secret: secret)

        #expect(verifier.isValidSignature(header, body: body) == false)
    }

    @Test("accepts an upper-cased hex digest")
    func acceptsUppercasedDigest() {
        let signature = GitHubWebhookSigner.sign(body: body, secret: secret)
        let uppercased = GitHubWebhookSignatureVerifier.signaturePrefix
        + signature.dropFirst(GitHubWebhookSignatureVerifier.signaturePrefix.count).uppercased()
        let verifier = GitHubWebhookSignatureVerifier(secret: secret)

        #expect(verifier.isValidSignature(uppercased, body: body))
    }

    @Test("matches the digest GitHub's documented example produces")
    func matchesKnownDigest() {
        // From GitHub's webhook documentation: HMAC-SHA256 of "Hello, World!" under "It's a Secret to Everybody".
        let signature = GitHubWebhookSigner.sign(
            body: Data("Hello, World!".utf8),
            secret: "It's a Secret to Everybody"
        )

        #expect(
            signature
            == "sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17"
        )
    }
}
