import GitHubAccessModels

/// The `installation` webhook: the App was installed, uninstalled, suspended, unsuspended, or
/// had new permissions accepted.
public struct GitHubInstallationEvent: GitHubWebhookEvent {
    public static let eventName: GitHubEventName = "installation"

    /// `created`, `deleted`, `suspend`, `unsuspend` or `new_permissions_accepted`.
    public let action: String
    public let installation: GitHubInstallation
}

/// The `installation_repositories` webhook: repositories were added to or removed from an installation.
public struct GitHubInstallationRepositoriesEvent: GitHubWebhookEvent {
    public static let eventName: GitHubEventName = "installation_repositories"

    /// `added` or `removed`.
    public let action: String
    public let installation: GitHubInstallation
}

extension GitHubEventKey where Event == GitHubInstallationEvent {
    public static var installation: GitHubEventKey<GitHubInstallationEvent> { .init() }
}

extension GitHubEventKey where Event == GitHubInstallationRepositoriesEvent {
    public static var installationRepositories: GitHubEventKey<GitHubInstallationRepositoriesEvent> { .init() }
}
