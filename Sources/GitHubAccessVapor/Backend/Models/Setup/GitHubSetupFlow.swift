import Foundation
import GitHubAccessModels
import Vapor

/// Why a setup redirect was not accepted.
///
/// The cases are for the host's logs. What a browser is told should be one message for all of
/// them (see `Vapor/Application/GitHubAccess/mountSetupCallback(at:store:respond:)`), so that the
/// callback cannot be used to find out which installations or states exist.
public enum GitHubSetupError: Error, Sendable, Equatable {
    /// No `state`, or one that was not issued, was already used, has expired, or was issued for something else.
    case invalidState
    /// GitHub does not know the claimed installation as one of this App's.
    case unknownInstallation(Int64)
}

/// The start and finish of installing the App, with the redirect verified.
///
/// GitHub sends the administrator's browser back with an `installation_id` in the URL. Anyone can
/// type that URL, so nothing in it is believed until two things hold: its `state` is one this flow
/// issued (single use, still fresh), and GitHub, asked with the App's own key, confirms the
/// installation exists. Without the second check an administrator could claim someone else's
/// installation; without the first, anyone could walk the callback.
///
/// ```swift
/// let flow = app.gitHubAccess.setup(states: InMemoryGitHubSetupStateStore())
/// let invitation = try await flow.begin(for: "admin-subject")   // send invitation.url to the browser
/// // … GitHub redirects back; mountSetupCallback calls flow.complete(_:) for you.
/// ```
public struct GitHubSetupFlow: Sendable {

    /// Where to send the administrator, and what to expect back.
    public struct Invitation: Sendable, Equatable {
        /// `https://github.com/apps/<slug>/installations/new?state=…`.
        public let url: URL
        public let state: String
        public let expiresAt: Date
    }

    /// What a verified redirect amounts to.
    public enum Outcome: Sendable, Equatable {
        /// The App is installed (or its installation changed) and GitHub confirmed it.
        case installed(GitHubInstallation, subject: String)
        /// A user asked an organization owner to approve the installation. There is no installation yet.
        case requested(subject: String)
    }

    internal let access: Application.GitHubAccess
    internal let states: any GitHubSetupStateStore
    /// How long an invitation stays valid. Ten minutes covers signing in and confirming on GitHub.
    public var lifetime: TimeInterval = 600

    internal init(access: Application.GitHubAccess, states: any GitHubSetupStateStore) {
        self.access = access
        self.states = states
    }

    /// Starts an installation for `subject`.
    ///
    /// - Throws: ``GitHubAPIError`` if the App's slug cannot be fetched (the credentials are wrong or GitHub is unreachable).
    public func begin(for subject: String, now: Date = Date()) async throws -> Invitation {
        let slug = try await access.appSlug()
        let state = try await states.issue(for: subject, purpose: .install, lifetime: lifetime, now: now)
        let link = try GitHubInstallLink(appSlug: slug, state: state)
        return Invitation(url: link.url, state: state, expiresAt: now.addingTimeInterval(lifetime))
    }

    /// Verifies a redirect.
    ///
    /// The state is consumed first and whatever follows, so a redirect gets one attempt.
    ///
    /// - Throws: ``GitHubSetupError``; or ``GitHubAPIError`` if GitHub could not be asked.
    public func complete(_ callback: GitHubSetupCallback, now: Date = Date()) async throws -> Outcome {
        guard let state = callback.state, let subject = try await states.consume(state, purpose: .install, now: now) else {
            throw GitHubSetupError.invalidState
        }
        if callback.setupAction == .request { return .requested(subject: subject) }
        guard let id = callback.installationID else { throw GitHubSetupError.invalidState }

        do {
            return .installed(try await access.installation(id: id), subject: subject)
        } catch let error as GitHubAPIError where error.kind == .notFound {
            throw GitHubSetupError.unknownInstallation(id)
        }
    }
}

extension Application.GitHubAccess {

    /// The installation flow, with `states` remembering what was issued.
    public func setup(states: any GitHubSetupStateStore) -> GitHubSetupFlow {
        GitHubSetupFlow(access: self, states: states)
    }

    /// Mounts `GET path`, GitHub's redirect target after an installation, and answers it only for a verified redirect.
    ///
    /// Set the App's *Setup URL* to this route. The route is deliberately outside any user
    /// authentication, because GitHub's redirect carries none: the `state` is what authenticates it.
    ///
    /// - Parameters:
    ///   - path: The route, such as `["github", "installed"]`. It must not be `github/setup`, which
    ///     belongs to the page `Vapor/Application/configureSetupPage(project:accent:servesAssets:)` mounts.
    ///   - store: Where the confirmed installation is saved before `respond` runs, if given.
    ///   - respond: Builds the browser's answer, usually a redirect into the web console or the app's URL scheme.
    ///     Only called for a verified outcome.
    /// - Returns: The flow to call ``GitHubSetupFlow/begin(for:now:)`` on, sharing this route's state store.
    @discardableResult
    public func mountSetupCallback(
        at path: [PathComponent],
        states: any GitHubSetupStateStore,
        store: (any GitHubInstallationStore)? = nil,
        respond: @escaping @Sendable (GitHubSetupFlow.Outcome, Request) async throws -> Response
    ) -> GitHubSetupFlow {
        let flow = setup(states: states)
        let application = self.store.application
        application.routes.get(path) { request async throws -> Response in
            let callback: GitHubSetupCallback
            do {
                callback = try GitHubSetupCallback(queryItems: (URLComponents(string: request.url.string)?.queryItems ?? []))
            } catch {
                throw Abort(.badRequest, reason: Application.GitHubAccess.refusal)
            }
            let outcome: GitHubSetupFlow.Outcome
            do {
                outcome = try await flow.complete(callback)
            } catch let error as GitHubSetupError {
                request.logger.notice("GitHub setup redirect refused: \(error)")
                throw Abort(.badRequest, reason: Application.GitHubAccess.refusal)
            }
            if case .installed(let installation, _) = outcome, let store {
                try await store.save(installation)
            }
            return try await respond(outcome, request)
        }
        return flow
    }

    internal static let refusal = "This GitHub setup link is not valid. Start again from the app."
}
