//
//  Application+Configuration.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 16/04/2026.
//

import Vapor

/// Who may call `POST /github/token`, which hands out installation tokens.
///
/// An installation token can read and clone every repository the installation covers, so the
/// route that issues them is the most sensitive one in the package. Until 3.0 it was open to anyone
/// who could reach the server and knew an installation ID; it is now off unless the host chooses.
public enum GitHubTokenAccess: Sendable {
    /// The route answers `404`. Tokens are still available in-process through `app.gitHubAccess`.
    case disabled
    /// The route runs `authenticate` first and answers only if it returns; it throws to refuse
    /// (typically `Abort(.unauthorized)`), and sees the whole request, so it can check a header,
    /// a client certificate or the peer's address.
    case authenticated(@Sendable (Request) async throws -> Void)
    /// The route answers anyone who can reach it: the behaviour before 3.0, for servers that are
    /// reachable only from a trusted network. Naming it makes that choice visible in the code.
    case unauthenticated
}

extension Application {

    /// Mounts the access server: the OpenAPI routes (`/health`, and `/github/token` if ``GitHubTokenAccess`` allows) and the
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
    ///   - tokens: Who may call `POST /github/token`; see ``GitHubTokenAccess``. Off by default.
    public func configureAccessServer(
        project: String,
        accent hex: String,
        servesAssets: Bool = true,
        userAgent: String = GitHubAccessConfiguration.defaultUserAgent,
        tokens: GitHubTokenAccess = .disabled
    ) async throws {
        gitHubAccess.configuration.userAgent = userAgent
        try await gitHubAccess.prepare()

        let controller = GitHubAccessController(app: self)
        try routes.grouped(GitHubTokenGuard(access: tokens)).register(collection: controller)

        if servesAssets {
            middleware.use(FileMiddleware(publicDirectory: directory.publicDirectory))
        }

        try await configureRoutes(project: project, accent: hex)
    }

    /// Mounts only the `/github/setup` redirect page.
    ///
    /// For hosts whose clients sign in to GitHub themselves, with user access tokens, and need
    /// nothing minted here: GitHub's install redirect still has to land on an `https` page that
    /// bounces the browser back into the app. Reads no GitHub App configuration, so the host needs
    /// neither an app ID nor a private key, and mounts neither `/health` nor `/github/token`.
    ///
    /// - Parameters:
    ///   - project: The project name shown on the setup page, also used as its URL scheme.
    ///   - hex: The accent colour of the setup page, as a hex string.
    ///   - servesAssets: Whether to install `FileMiddleware`, which serves the setup page's
    ///     `/logo.svg` from the public directory.
    public func configureSetupPage(
        project: String,
        accent hex: String,
        servesAssets: Bool = true
    ) async throws {
        if servesAssets {
            middleware.use(FileMiddleware(publicDirectory: directory.publicDirectory))
        }

        try await configureRoutes(project: project, accent: hex)
    }
}

/// Applies ``GitHubTokenAccess`` to `/github/token` and leaves every other route alone.
internal struct GitHubTokenGuard: AsyncMiddleware {
    let access: GitHubTokenAccess

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard request.url.path == "/github/token" else { return try await next.respond(to: request) }
        switch access {
        case .disabled: throw Abort(.notFound)
        case .authenticated(let authenticate):
            try await authenticate(request)
            return try await next.respond(to: request)
        case .unauthenticated: return try await next.respond(to: request)
        }
    }
}
