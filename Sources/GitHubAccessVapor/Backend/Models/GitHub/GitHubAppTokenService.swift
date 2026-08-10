//
//  GitHubAppTokenService.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 25/03/2026.
//

import Foundation

import Vapor
import JWTKit

internal struct GitHubAppTokenService: Sendable {

    /// The `User-Agent` GitHub is addressed with when no other value is configured.
    internal static let defaultUserAgent = GitHubAccessConfiguration.defaultUserAgent

    internal let app: Application
    internal let appID: String
    internal let privateKeyPEM: String
    internal let userAgent: String

    /// - Parameters:
    ///   - app: The application whose `client` and `logger` are used.
    ///   - userAgent: The `User-Agent` sent to GitHub. Defaults to ``defaultUserAgent``.
    internal init(app: Application, userAgent: String = GitHubAppTokenService.defaultUserAgent) throws {
        let appID = try GitHubConfiguration.value(named: GitHubConfiguration.appIDKey)
        let privateKeyPEM = try Self.resolvedPrivateKeyPEM()

        self.app = app
        self.appID = appID
        self.privateKeyPEM = privateKeyPEM
        self.userAgent = userAgent
    }

    internal func createInstallationToken(for installationID: Int64) async throws -> GitHubInstallationToken {
        let jwt = try await githubAppJWT()
        return try await createInstallationToken(installationID: installationID, jwt: jwt)
    }

    /// Loads the app's private key from `GITHUB_PRIVATE_KEY_PATH`, falling back to the PEM held
    /// inline in `GITHUB_PRIVATE_KEY`.
    ///
    /// The path wins when both are set. Containers and CI runners commonly inject secrets as
    /// environment variables rather than files, and such values often carry escaped newlines, so a
    /// single-line inline PEM has its `\n` sequences restored.
    private static func resolvedPrivateKeyPEM() throws -> String {
        if let path = GitHubConfiguration.optionalValue(named: GitHubConfiguration.privateKeyPathKey) {
            return try String(contentsOfFile: path, encoding: .utf8)
        }

        if let inline = GitHubConfiguration.optionalValue(named: GitHubConfiguration.privateKeyKey) {
            guard inline.contains("\n") else {
                return inline.replacingOccurrences(of: "\\n", with: "\n")
            }

            return inline
        }

        throw Abort(
            .badRequest,
            reason: "Missing configuration value '\(GitHubConfiguration.privateKeyPathKey)' or '\(GitHubConfiguration.privateKeyKey)'."
        )
    }

    private func githubAppJWT() async throws -> String {
        let payload = GitHubAppPayload(appID: appID)
        let privateKey = try Insecure.RSA.PrivateKey(pem: privateKeyPEM)
        let keys = JWTKeyCollection()
        await keys.add(rsa: privateKey, digestAlgorithm: .sha256)

        return try await keys.sign(payload)
    }

    private func createInstallationToken(
        installationID: Int64,
        jwt: String
    ) async throws -> GitHubInstallationToken {
        let response = try await app.client.post(
            URI(string: "https://api.github.com/app/installations/\(installationID)/access_tokens")
        ) { request in
            request.headers.bearerAuthorization = .init(token: jwt)
            request.headers.add(name: .accept, value: "application/vnd.github+json")
            request.headers.add(name: .userAgent, value: userAgent)
            request.headers.add(name: .init("X-GitHub-Api-Version"), value: "2026-03-10")
        }

        guard response.status == .created else {
            let body = response.body.flatMap { buffer in
                buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes)
            } ?? "No response body"

            app.logger.error("GitHub token request failed: \(response.status.code) \(body)")
            throw Abort(.internalServerError, reason: "GitHub rejected the installation token request.")
        }

        guard let body = response.body else {
            throw Abort(.internalServerError, reason: "GitHub did not return a response body.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(GitHubInstallationToken.self, from: Data(buffer: body))
    }
}
