import GitHubAccessModels
import Vapor

extension Application.GitHubAccess {

    /// Keeps `store` current from the App's `installation` and `installation_repositories` webhooks.
    ///
    /// Needs the webhook route to be mounted, which is the host's to do. A removed installation is
    /// deleted from the store; any other event saves the installation as the event describes it.
    /// Webhooks can be missed, so pair this with `reconcileInstallations(in:)`.
    public func keepInstallations(in store: any GitHubInstallationStore) {
        let events = self.store.application.gitHubEvents
        events.on(.installation) { event, _ in
            if event.action == "deleted" {
                try await store.remove(id: event.installation.id)
            } else {
                try await store.save(event.installation)
            }
        }
        events.on(.installationRepositories) { event, _ in
            try await store.save(event.installation)
        }
    }

    /// Makes `store` match what GitHub lists, and returns what changed.
    ///
    /// Run it at start-up and now and then: an installation removed while the host was down would
    /// otherwise stay in the store, and keep being offered for work that will fail with a `404`.
    @discardableResult
    public func reconcileInstallations(in store: any GitHubInstallationStore) async throws -> (added: [Int64], removed: [Int64]) {
        let listed = try await installations()
        let known = Set(try await store.all().map(\.id))
        let current = Set(listed.map(\.id))
        for installation in listed { try await store.save(installation) }
        let gone = known.subtracting(current)
        for id in gone { try await store.remove(id: id) }
        return (added: current.subtracting(known).sorted(), removed: gone.sorted())
    }
}
