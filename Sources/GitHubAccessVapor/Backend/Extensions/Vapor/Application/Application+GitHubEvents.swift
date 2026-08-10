//
//  Application+GitHubEvents.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Vapor

extension Application {

    /// The registry of GitHub webhook handlers.
    ///
    /// ```swift
    /// app.gitHubEvents.on(.release) { event, request in
    ///     guard event.action == .published else { return }
    ///     // …
    /// }
    /// ```
    ///
    /// Handlers can be registered before or after `configureWebhooks(secret:path:)` mounts the
    /// route; nothing reaches them until a delivery's signature has been verified.
    public var gitHubEvents: GitHubEventDispatcher {
        if let existing = storage[GitHubEventsKey.self] {
            return existing
        }

        let lock = locks.lock(for: GitHubEventsKey.self)
        lock.lock()
        defer { lock.unlock() }

        if let existing = storage[GitHubEventsKey.self] {
            return existing
        }

        let dispatcher = GitHubEventDispatcher()
        storage[GitHubEventsKey.self] = dispatcher

        return dispatcher
    }

    private struct GitHubEventsKey: StorageKey, LockKey {
        typealias Value = GitHubEventDispatcher
    }
}
