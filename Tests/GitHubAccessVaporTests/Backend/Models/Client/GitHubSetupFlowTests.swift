import Foundation
import GitHubAccessModels
import GitHubAccessVapor
import GitHubAccessVaporTesting
import NIOCore
import Testing
import Vapor
import VaporTesting

@testable import GitHubAccessVapor

@Suite("GitHub setup flows", .serialized)
struct GitHubSetupFlowTests {

    private func withGitHub(_ body: (Application, FakeGitHub) async throws -> Void) async throws {
        let github = try await FakeGitHub()
        let app = try await Application.make(.testing)
        do {
            app.gitHubAccess.configuration.apiBaseURL = github.baseURL
            await app.gitHubAccess.useCredentials(GitHubAppCredentials(appID: github.appID, privateKeyPEM: TestAppKey.pem))
            try await body(app, github)
        } catch {
            try? await app.asyncShutdown()
            await github.shutdown()
            throw error
        }
        try await app.asyncShutdown()
        await github.shutdown()
    }

    private func state(of url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value ?? ""
    }

    // MARK: State store

    @Test("a state is redeemable once, by its purpose, before it expires")
    func stateStore() async throws {
        let store = InMemoryGitHubSetupStateStore()
        let now = Date()
        let first = try await store.issue(for: "admin", purpose: .install, lifetime: 60, now: now)
        #expect(try await store.consume(first, purpose: .manifest, now: now) == nil)  // wrong purpose burns it
        #expect(try await store.consume(first, purpose: .install, now: now) == nil)

        let second = try await store.issue(for: "admin", purpose: .install, lifetime: 60, now: now)
        #expect(try await store.consume(second, purpose: .install, now: now) == "admin")
        #expect(try await store.consume(second, purpose: .install, now: now) == nil)

        let third = try await store.issue(for: "admin", purpose: .install, lifetime: 60, now: now)
        #expect(try await store.consume(third, purpose: .install, now: now.addingTimeInterval(61)) == nil)
        #expect(first != second && second != third)
        #expect(first.count >= 40)
    }

    // MARK: Install

    @Test("an install invitation carries the App's slug and a fresh state")
    func invitation() async throws {
        try await withGitHub { app, github in
            github.appSlug = "my-manager"
            let flow = app.gitHubAccess.setup(states: InMemoryGitHubSetupStateStore())
            let invitation = try await flow.begin(for: "admin")
            #expect(invitation.url.absoluteString.hasPrefix("https://github.com/apps/my-manager/installations/new?state="))
            #expect(state(of: invitation.url) == invitation.state)
        }
    }

    @Test("a verified redirect completes once and reports the installation")
    func completes() async throws {
        try await withGitHub { app, github in
            github.addInstallation(GitHubInstallation(id: 7))
            let flow = app.gitHubAccess.setup(states: InMemoryGitHubSetupStateStore())
            let invitation = try await flow.begin(for: "admin")
            let callback = try GitHubSetupCallback(installationID: 7, setupAction: .install, state: invitation.state)

            let outcome = try await flow.complete(callback)
            #expect(outcome == .installed(GitHubInstallation(id: 7), subject: "admin"))
            await #expect(throws: GitHubSetupError.invalidState) { _ = try await flow.complete(callback) }
        }
    }

    @Test("an installation GitHub does not list is refused, and still spends the state")
    func unknownInstallation() async throws {
        try await withGitHub { app, _ in
            let flow = app.gitHubAccess.setup(states: InMemoryGitHubSetupStateStore())
            let invitation = try await flow.begin(for: "admin")
            let callback = try GitHubSetupCallback(installationID: 999, setupAction: .install, state: invitation.state)
            await #expect(throws: GitHubSetupError.unknownInstallation(999)) { _ = try await flow.complete(callback) }
            await #expect(throws: GitHubSetupError.invalidState) { _ = try await flow.complete(callback) }
        }
    }

    @Test("a redirect with no state, or one nobody issued, is refused without asking GitHub")
    func invalidState() async throws {
        try await withGitHub { app, github in
            github.addInstallation(GitHubInstallation(id: 7))
            let flow = app.gitHubAccess.setup(states: InMemoryGitHubSetupStateStore())
            let none = try GitHubSetupCallback(installationID: 7, setupAction: .install)
            let forged = try GitHubSetupCallback(installationID: 7, setupAction: .install, state: "forged")
            await #expect(throws: GitHubSetupError.invalidState) { _ = try await flow.complete(none) }
            await #expect(throws: GitHubSetupError.invalidState) { _ = try await flow.complete(forged) }
            #expect(github.requests.isEmpty)
        }
    }

    @Test("an approval request is reported as a request, not an installation")
    func approvalRequested() async throws {
        try await withGitHub { app, github in
            let flow = app.gitHubAccess.setup(states: InMemoryGitHubSetupStateStore())
            let invitation = try await flow.begin(for: "admin")
            let callback = try GitHubSetupCallback(installationID: nil, setupAction: .request, state: invitation.state)
            let outcome = try await flow.complete(callback)
            #expect(outcome == .requested(subject: "admin"))
            #expect(!github.requests.contains { $0.path.hasPrefix("/app/installations") })
        }
    }

    @Test("the mounted callback saves the installation and answers only for a verified redirect")
    func mountedCallback() async throws {
        try await withGitHub { app, github in
            github.addInstallation(GitHubInstallation(id: 7))
            let store = InMemoryGitHubInstallationStore()
            let states = InMemoryGitHubSetupStateStore()
            let flow = app.gitHubAccess.mountSetupCallback(at: ["github", "installed"], states: states, store: store) { outcome, _ in
                guard case .installed(let installation, let subject) = outcome else { return Response(status: .accepted) }
                return Response(status: .ok, body: .init(string: "\(installation.id) for \(subject)"))
            }
            let invitation = try await flow.begin(for: "admin")

            try await app.testing().test(.GET, "github/installed?installation_id=7&setup_action=install&state=forged") { response async in
                #expect(response.status == .badRequest)
                #expect(!response.body.string.contains("forged"))
            }
            #expect(try await store.all().isEmpty)

            try await app.testing().test(.GET, "github/installed?installation_id=7&setup_action=install&state=\(invitation.state)") { response async in
                #expect(response.status == .ok)
                #expect(response.body.string == "7 for admin")
            }
            #expect(try await store.all().map(\.id) == [7])
        }
    }

    // MARK: Manifest

    private let manifest = GitHubAppManifest.serverManager(
        name: "Funico Server Manager", url: URL(string: "https://manager.example.com")!,
        webhookURL: URL(string: "https://manager.example.com/github/webhook")!,
        redirectURL: URL(string: "https://manager.example.com/github/created")!,
        setupURL: URL(string: "https://manager.example.com/github/installed")!
    )

    @Test("a manifest registration is bound to its subject and redeemed once for the credentials")
    func manifestFlow() async throws {
        try await withGitHub { app, github in
            let conversion = GitHubAppManifestConversion(
                id: 99, slug: "created", clientID: "Iv1.x", clientSecret: "client-secret", webhookSecret: "hook-secret", pem: "PEM"
            )
            github.addManifestConversion(code: "abc123", conversion)
            let flow = app.gitHubAccess.manifest(states: InMemoryGitHubSetupStateStore())
            let registration = try await flow.begin(manifest, for: "admin")

            await #expect(throws: GitHubSetupError.invalidState) { _ = try await flow.complete(code: "abc123", state: "forged") }
            let result = try await flow.complete(code: "abc123", state: registration.state)
            #expect(result.subject == "admin")
            #expect(result.conversion.id == 99)
            #expect(result.conversion.pem == "PEM")
            await #expect(throws: GitHubSetupError.invalidState) { _ = try await flow.complete(code: "abc123", state: registration.state) }
            #expect(github.requests.filter { $0.path.hasPrefix("/app-manifests") }.allSatisfy { $0.authorization == nil })
        }
    }

    @Test("a manifest code that is not a plain token never reaches GitHub")
    func manifestCodeShape() async throws {
        try await withGitHub { app, github in
            let flow = app.gitHubAccess.manifest(states: InMemoryGitHubSetupStateStore())
            let registration = try await flow.begin(manifest, for: "admin")
            await #expect(throws: GitHubSetupError.invalidState) { _ = try await flow.complete(code: "../app", state: registration.state) }
            #expect(github.requests.isEmpty)
        }
    }

    @Test("the mounted manifest callback hands the secrets to the host and to no one else")
    func mountedManifestCallback() async throws {
        try await withGitHub { app, github in
            github.addManifestConversion(code: "abc123", GitHubAppManifestConversion(
                id: 99, slug: "created", clientID: "Iv1.x", clientSecret: "client-secret", webhookSecret: "hook-secret", pem: "PEM"
            ))
            let flow = app.gitHubAccess.mountManifestCallback(at: ["github", "created"], states: InMemoryGitHubSetupStateStore()) { conversion, subject, _ in
                Response(status: .ok, body: .init(string: "\(conversion.slug) \(subject)"))
            }
            let registration = try await flow.begin(manifest, for: "admin")

            try await app.testing().test(.GET, "github/created?code=abc123&state=forged") { response async in
                #expect(response.status == .badRequest)
            }
            try await app.testing().test(.GET, "github/created?code=abc123&state=\(registration.state)") { response async in
                #expect(response.status == .ok)
                #expect(response.body.string == "created admin")
                #expect(!response.body.string.contains("PEM"))
            }
        }
    }

    // MARK: Installation store

    @Test("webhooks add, change and remove installations in the store")
    func webhooksKeepStoreCurrent() async throws {
        try await withGitHub { app, _ in
            let store = InMemoryGitHubInstallationStore()
            app.gitHubAccess.keepInstallations(in: store)
            try app.configureWebhooks(secret: .value("s"), path: "github", "webhook")

            func deliver(_ event: String, _ json: String) async throws {
                let body = Data(json.utf8)
                try await app.testing().test(
                    .POST, "/github/webhook", headers: GitHubWebhookFixture.headers(body: body, secret: "s", event: event),
                    body: ByteBuffer(data: body)
                ) { response async in #expect(response.status == .accepted) }
            }
            func settled(_ condition: () async throws -> Bool) async throws {
                for _ in 0..<100 { if try await condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
            }

            try await deliver("installation", #"{"action":"created","installation":{"id":5,"repository_selection":"all"}}"#)
            try await settled { try await store.installation(id: 5) != nil }
            #expect(try await store.installation(id: 5)?.repositorySelection == .all)

            try await deliver("installation_repositories", #"{"action":"removed","installation":{"id":5,"repository_selection":"selected"}}"#)
            try await settled { try await store.installation(id: 5)?.repositorySelection == .selected }
            #expect(try await store.installation(id: 5)?.repositorySelection == .selected)

            try await deliver("installation", #"{"action":"deleted","installation":{"id":5}}"#)
            try await settled { try await store.installation(id: 5) == nil }
            #expect(try await store.installation(id: 5) == nil)
        }
    }

    @Test("reconciling makes the store match GitHub and reports the difference")
    func reconcile() async throws {
        try await withGitHub { app, github in
            let store = InMemoryGitHubInstallationStore()
            try await store.save(GitHubInstallation(id: 1))
            try await store.save(GitHubInstallation(id: 2))
            github.addInstallation(GitHubInstallation(id: 2))
            github.addInstallation(GitHubInstallation(id: 3))

            let changes = try await app.gitHubAccess.reconcileInstallations(in: store)
            #expect(changes.added == [3])
            #expect(changes.removed == [1])
            #expect(try await store.all().map(\.id) == [2, 3])
        }
    }

    // MARK: Token route

    @Test("the token route is off unless the host turns it on")
    func tokenRoute() async throws {
        try await withGitHub { app, github in
            github.addInstallation(GitHubInstallation(id: 7))
            try await app.configureAccessServer(project: "App", accent: "000000", servesAssets: false)
            try await app.testing().test(.POST, "github/token", headers: ["Content-Type": "application/json"], body: ByteBuffer(string: #"{"installationId":7}"#)) { response async in
                #expect(response.status == .notFound)
            }
            try await app.testing().test(.GET, "health") { response async in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("an authenticated token route runs the host's check first; unauthenticated is the old behaviour")
    func tokenRouteModes() async throws {
        struct Refused: Error {}
        try await withGitHub { app, github in
            github.addInstallation(GitHubInstallation(id: 7))
            try await app.configureAccessServer(
                project: "App", accent: "000000", servesAssets: false,
                tokens: .authenticated { request in
                    guard request.headers.first(name: "X-Key") == "k" else { throw Abort(.unauthorized) }
                }
            )
            let body = ByteBuffer(string: #"{"installationId":7}"#)
            try await app.testing().test(.POST, "github/token", headers: ["Content-Type": "application/json"], body: body) { response async in
                #expect(response.status == .unauthorized)
            }
            try await app.testing().test(.POST, "github/token", headers: ["Content-Type": "application/json", "X-Key": "k"], body: body) { response async in
                #expect(response.status == .ok)
            }
        }
        try await withGitHub { app, github in
            github.addInstallation(GitHubInstallation(id: 7))
            try await app.configureAccessServer(project: "App", accent: "000000", servesAssets: false, tokens: .unauthenticated)
            try await app.testing().test(.POST, "github/token", headers: ["Content-Type": "application/json"], body: ByteBuffer(string: #"{"installationId":7}"#)) { response async in
                #expect(response.status == .ok)
            }
        }
    }
}
