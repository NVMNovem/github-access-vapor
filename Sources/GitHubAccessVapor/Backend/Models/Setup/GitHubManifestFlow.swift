import Foundation
import GitHubAccessModels
import Vapor

/// Creating the GitHub App itself from a manifest, so that nobody copies an App ID and a private key by hand.
///
/// The administrator's browser posts the manifest to GitHub and confirms there; GitHub redirects back
/// with a one-time `code`; the server trades the code for the App's ID, private key, webhook secret
/// and client secret. Those secrets exist in exactly one response. This flow hands them to the host
/// once, in the closure given to `Vapor/Application/GitHubAccess/mountManifestCallback(at:states:respond:)`,
/// and does not log, return or store them: the host puts them in its secret store.
public struct GitHubManifestFlow: Sendable {

    internal let access: Application.GitHubAccess
    internal let states: any GitHubSetupStateStore
    /// How long a registration stays valid. Creating an App takes longer than installing one.
    public var lifetime: TimeInterval = 900

    internal init(access: Application.GitHubAccess, states: any GitHubSetupStateStore) {
        self.access = access
        self.states = states
    }

    /// Prepares the registration form for `subject`.
    public func begin(
        _ manifest: GitHubAppManifest, owner: GitHubAppManifest.Owner = .user, for subject: String, now: Date = Date()
    ) async throws -> GitHubAppManifest.Registration {
        let state = try await states.issue(for: subject, purpose: .manifest, lifetime: lifetime, now: now)
        return try manifest.registration(for: owner, state: state)
    }

    /// Verifies the redirect and trades `code` for the App's credentials.
    ///
    /// - Throws: ``GitHubSetupError/invalidState``; or ``GitHubAPIError`` if GitHub refuses the code
    ///   (it is single use and expires after an hour).
    public func complete(code: String, state: String, now: Date = Date()) async throws -> (conversion: GitHubAppManifestConversion, subject: String) {
        guard let subject = try await states.consume(state, purpose: .manifest, now: now) else {
            throw GitHubSetupError.invalidState
        }
        guard !code.isEmpty, code.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw GitHubSetupError.invalidState
        }
        let conversion = try await GitHubAPI(access.store.application).json(
            GitHubAppManifestConversion.self, .POST, "/app-manifests/\(code)/conversions", auth: .none, success: [.created]
        )
        return (conversion, subject)
    }
}

extension Application.GitHubAccess {

    /// The App-creation flow, with `states` remembering what was issued.
    public func manifest(states: any GitHubSetupStateStore) -> GitHubManifestFlow {
        GitHubManifestFlow(access: self, states: states)
    }

    /// Mounts `GET path`, the manifest's `redirect_url`, and answers it only for a verified redirect.
    ///
    /// - Parameter respond: Receives the new App's credentials and the subject who started the flow.
    ///   Store the secrets, call `useCredentials(_:)`, and answer the browser. The conversion's own
    ///   description redacts its secrets, but do not log it anyway.
    @discardableResult
    public func mountManifestCallback(
        at path: [PathComponent],
        states: any GitHubSetupStateStore,
        respond: @escaping @Sendable (GitHubAppManifestConversion, _ subject: String, Request) async throws -> Response
    ) -> GitHubManifestFlow {
        let flow = manifest(states: states)
        let application = self.store.application
        application.routes.get(path) { request async throws -> Response in
            guard let code = request.query[String.self, at: "code"], let state = request.query[String.self, at: "state"] else {
                throw Abort(.badRequest, reason: Application.GitHubAccess.manifestRefusal)
            }
            let result: (conversion: GitHubAppManifestConversion, subject: String)
            do {
                result = try await flow.complete(code: code, state: state)
            } catch let error as GitHubSetupError {
                request.logger.notice("GitHub manifest redirect refused: \(error)")
                throw Abort(.badRequest, reason: Application.GitHubAccess.manifestRefusal)
            } catch let error as GitHubAPIError {
                request.logger.error("GitHub refused the manifest code: status \(error.status)")
                throw Abort(.badGateway, reason: "GitHub did not complete the App registration.")
            }
            return try await respond(result.conversion, result.subject, request)
        }
        return flow
    }

    internal static let manifestRefusal = "This GitHub registration link is not valid. Start again from the app."
}
