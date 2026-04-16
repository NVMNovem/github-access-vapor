//
//  GitHubAppTokenService.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 25/03/2026.
//

import Foundation

import Vapor
import JWTKit

internal struct GitHubAppTokenService {
    
    internal let app: Application
    internal let appID: String
    internal let privateKeyPEM: String
    
    internal init(app: Application) throws {
        let appID = try Self.configurationValue(named: "GITHUB_APP_ID")
        let path = try Self.configurationValue(named: "GITHUB_PRIVATE_KEY_PATH")
        let privateKeyPEM = try String(contentsOfFile: path, encoding: .utf8)
        
        self.app = app
        self.appID = appID
        self.privateKeyPEM = privateKeyPEM
    }
    
    internal func createInstallationToken(for installationID: Int64) async throws -> GitHubInstallationToken {
        let jwt = try await githubAppJWT()
        return try await createInstallationToken(installationID: installationID, jwt: jwt)
    }
    
    private static func configurationValue(named key: String) throws -> String {
        guard let value = Environment.get(key), !value.isEmpty else {
            throw Abort(.badRequest, reason: "Missing configuration value '\(key)'.")
        }
        
        return value
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
            request.headers.add(name: .userAgent, value: "GitSyncAccessServer")
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
