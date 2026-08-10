//
//  GitHubEventRecorder.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

@testable import GitHubAccessVapor

/// Collects what webhook handlers received, so tests can assert on work that happens after the
/// route has already answered.
internal actor GitHubEventRecorder {

    private(set) var releases: [GitHubReleaseEvent] = []
    private(set) var deliveries: [GitHubWebhookDelivery] = []

    internal func record(_ event: GitHubReleaseEvent) {
        releases.append(event)
    }

    internal func record(_ delivery: GitHubWebhookDelivery) {
        deliveries.append(delivery)
    }

    /// Waits until `count` deliveries have been recorded, giving up after `timeout`.
    ///
    /// Returns rather than failing, so the caller's expectation reports the mismatch.
    internal func waitForDeliveries(_ count: Int, timeout: Duration = .seconds(2)) async {
        await wait(timeout: timeout) { self.deliveries.count >= count }
    }

    /// Waits until `count` release events have been recorded, giving up after `timeout`.
    internal func waitForReleases(_ count: Int, timeout: Duration = .seconds(2)) async {
        await wait(timeout: timeout) { self.releases.count >= count }
    }

    /// Gives any in-flight handler a chance to run, for assertions that nothing was recorded.
    internal func settle(for duration: Duration = .milliseconds(250)) async {
        try? await Task.sleep(for: duration)
    }

    private func wait(timeout: Duration, until isSatisfied: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while !isSatisfied(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
