//
//  GitHubDeliveryDeduplicator.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

/// Remembers recent `X-GitHub-Delivery` identifiers so a retried delivery is handled once.
///
/// GitHub redelivers on timeouts and non-2xx responses, and a redelivered event must not run its
/// handler twice. Only a bounded window of recent identifiers is kept — the oldest is dropped once
/// ``capacity`` is reached. The window does not survive a restart: a retry arriving across one is
/// vanishingly unlikely, and handlers should be idempotent regardless.
internal actor GitHubDeliveryDeduplicator {

    /// The default number of delivery identifiers kept.
    internal static let defaultCapacity = 512

    internal let capacity: Int

    private var identifiers: Set<String> = []
    private var order: [String] = []

    internal init(capacity: Int = GitHubDeliveryDeduplicator.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// Records `identifier` and reports whether it is new.
    ///
    /// - Returns: `true` when this delivery has not been seen, and should be handled.
    internal func register(_ identifier: String) -> Bool {
        guard identifiers.insert(identifier).inserted else { return false }

        order.append(identifier)

        if order.count > capacity {
            let evicted = order.removeFirst()
            identifiers.remove(evicted)
        }

        return true
    }

    internal var count: Int { order.count }
}
