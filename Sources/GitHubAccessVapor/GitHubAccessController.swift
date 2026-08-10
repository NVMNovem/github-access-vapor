//
//  GitHubAccessController.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 16/04/2026.
//

import Vapor

import OpenAPIRuntime
import OpenAPIVapor

internal struct GitHubAccessController: RouteCollection, APIProtocol {
    
    private let app: Application

    internal init(app: Application) {
        self.app = app
    }

    internal func boot(routes: RoutesBuilder) throws {
        let transport = VaporTransport(routesBuilder: routes)
        try registerHandlers(on: transport, serverURL: Servers.Server1.url())
    }
    
    internal func createGitHubToken(_ input: Operations.CreateGitHubToken.Input) async throws -> Operations.CreateGitHubToken.Output {
        switch input.body {
        case .json(let createGitHubToken):
            let installationId = try createGitHubToken.validated(\.installationId)
            
            let token = try await app.gitHubAccess.installationToken(for: installationId)
            
            return .ok(.init(body: .json(.init(
                token: token.token,
                expiresAt: token.expiresAt
            ))))
        }
    }
    
    internal func health(_ input: Operations.Health.Input) async throws -> Operations.Health.Output {
        .ok(.init(body: .json(.init(status: .ok))))
    }
}
