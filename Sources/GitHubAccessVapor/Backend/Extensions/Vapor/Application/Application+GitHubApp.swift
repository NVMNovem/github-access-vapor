import Foundation
import GitHubAccessModels
import Vapor

extension Application.GitHubAccess {

    /// The App's slug, which is what the install link is built from
    /// (`https://github.com/apps/<slug>/installations/new`).
    ///
    /// Fetched from `GET /app` once and remembered until the credentials change.
    public func appSlug() async throws -> String {
        try await store.appSlug {
            struct AppRecord: Decodable, Sendable { var slug: String }
            return try await GitHubAPI(store.application).json(AppRecord.self, .GET, "/app", auth: .app).slug
        }
    }

    /// One installation of this App, as GitHub reports it.
    ///
    /// This is how a claimed `installation_id` is verified: GitHub answers `404` for an installation
    /// that is not this App's, whoever the caller says they are.
    ///
    /// - Throws: ``GitHubAPIError`` with kind `.notFound` if the App has no such installation.
    public func installation(id: Int64) async throws -> GitHubInstallation {
        try await GitHubAPI(store.application).json(GitHubInstallation.self, .GET, "/app/installations/\(id)", auth: .app)
    }

    /// Every installation of this App, for a periodic reconciliation against missed webhooks.
    public func installations() async throws -> [GitHubInstallation] {
        try await GitHubAPI(store.application).pages([GitHubInstallation].self, "/app/installations", auth: .app) { $0 }
    }

    /// REST access as one installation: repositories, releases and release assets.
    ///
    /// The installation token is minted, cached and renewed by ``installationToken(for:)``; a token
    /// GitHub refuses is replaced once before the call fails.
    public func client(for installationID: Int64) -> GitHubInstallationClient {
        GitHubInstallationClient(installationID: installationID, api: GitHubAPI(store.application))
    }
}
