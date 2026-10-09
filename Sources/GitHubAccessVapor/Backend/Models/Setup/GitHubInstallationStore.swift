import GitHubAccessModels

/// The host's record of which installations of the App exist.
///
/// GitHub is the source of truth and webhooks are how the host hears about changes, but webhooks are
/// delivered at most a few times and can be missed while the host is down. So the store is kept
/// current by both: `Vapor/Application/GitHubAccess/keepInstallations(in:)` applies the events as
/// they arrive, and `Vapor/Application/GitHubAccess/reconcileInstallations(in:)` replaces the contents
/// with what GitHub lists, which is what to run at start-up and periodically.
public protocol GitHubInstallationStore: Sendable {
    /// The installation with `id`, or `nil` if the host has none.
    func installation(id: Int64) async throws -> GitHubInstallation?

    /// Every installation the host knows, ordered by ID.
    func all() async throws -> [GitHubInstallation]

    /// Adds `installation`, or replaces the one with the same ID.
    func save(_ installation: GitHubInstallation) async throws

    /// Forgets the installation with `id`. Removing one that is not there is not an error.
    func remove(id: Int64) async throws
}

/// A ``GitHubInstallationStore`` that lives in this process.
public actor InMemoryGitHubInstallationStore: GitHubInstallationStore {
    private var installations: [Int64: GitHubInstallation] = [:]

    public init() {}

    public func installation(id: Int64) async throws -> GitHubInstallation? { installations[id] }
    public func all() async throws -> [GitHubInstallation] { installations.values.sorted { $0.id < $1.id } }
    public func save(_ installation: GitHubInstallation) async throws { installations[installation.id] = installation }
    public func remove(id: Int64) async throws { installations[id] = nil }
}
