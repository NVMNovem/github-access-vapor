//
//  Application+Configuration.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 16/04/2026.
//

import Vapor

extension Application {

    /// Mounts the access server: the OpenAPI routes (`/health`, `/github/token`) and the
    /// `/github/setup` redirect page.
    ///
    /// Calling this is optional. `app.gitHubAccess` mints tokens in-process without it.
    ///
    /// - Parameters:
    ///   - project: The project name shown on the setup page, also used as its URL scheme.
    ///   - hex: The accent colour of the setup page, as a hex string.
    ///   - servesAssets: Whether to install `FileMiddleware`, which serves the setup page's
    ///     `/logo.svg` from the public directory. Hosts that already configure their own middleware
    ///     stack should pass `false`.
    ///   - userAgent: The `User-Agent` GitHub is addressed with.
    public func configureAccessServer(
        project: String,
        accent hex: String,
        servesAssets: Bool = true,
        userAgent: String = GitHubAccessConfiguration.defaultUserAgent
    ) async throws {
        gitHubAccess.configuration.userAgent = userAgent
        try await gitHubAccess.prepare()

        let controller = GitHubAccessController(app: self)
        try routes.register(collection: controller)

        if servesAssets {
            middleware.use(FileMiddleware(publicDirectory: directory.publicDirectory))
        }

        try await configureRoutes(project: project, accent: hex)
    }
}
