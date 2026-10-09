import Foundation

/// What a pending GitHub redirect was issued for.
public enum GitHubSetupPurpose: String, Sendable, Hashable {
    /// The install link of an existing App.
    case install
    /// The manifest registration that creates the App.
    case manifest
}

/// Remembers the `state` values handed to GitHub, so that the redirect coming back can be tied to the
/// administrator who started it.
///
/// A redirect is just a URL that anyone can open. `state` is the only thing that says "this is the
/// answer to the flow *I* started", which is why it must be unguessable, bound to the person
/// who began it, **single use**, and short-lived. Implementations must make
/// ``consume(_:purpose:now:)`` atomic: of two concurrent calls with the same value, one gets the
/// subject and the other `nil`.
///
/// ``InMemoryGitHubSetupStateStore`` is enough for one process. A Manager that runs several
/// instances behind a balancer needs a shared implementation, because the redirect may land on a
/// different instance than the one that issued the value.
public protocol GitHubSetupStateStore: Sendable {

    /// Records a fresh value for `subject` and returns it.
    ///
    /// - Parameters:
    ///   - subject: Who began the flow: whatever the host uses to identify the administrator.
    ///   - purpose: What the value may be redeemed for; a value issued for one purpose never
    ///     satisfies the other.
    ///   - lifetime: How long the value stays redeemable. Long enough to sign in to GitHub and
    ///     confirm, short enough that an abandoned flow cannot be resumed days later.
    func issue(for subject: String, purpose: GitHubSetupPurpose, lifetime: TimeInterval, now: Date) async throws -> String

    /// Redeems `state`, returning the subject it was issued to, or `nil` if it is unknown, expired,
    /// already redeemed, or was issued for another purpose. A value is gone after the first call
    /// whatever the answer: a redirect gets one attempt.
    func consume(_ state: String, purpose: GitHubSetupPurpose, now: Date) async throws -> String?
}

/// A ``GitHubSetupStateStore`` that lives in this process.
public actor InMemoryGitHubSetupStateStore: GitHubSetupStateStore {

    private struct Entry {
        var subject: String
        var purpose: GitHubSetupPurpose
        var expiresAt: Date
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public func issue(for subject: String, purpose: GitHubSetupPurpose, lifetime: TimeInterval, now: Date = Date()) async throws -> String {
        entries = entries.filter { $0.value.expiresAt > now }
        let state = Self.randomState()
        entries[state] = Entry(subject: subject, purpose: purpose, expiresAt: now.addingTimeInterval(lifetime))
        return state
    }

    public func consume(_ state: String, purpose: GitHubSetupPurpose, now: Date = Date()) async throws -> String? {
        guard let entry = entries.removeValue(forKey: state) else { return nil }
        guard entry.purpose == purpose, entry.expiresAt > now else { return nil }
        return entry.subject
    }

    /// 256 bits from the system's secure generator, URL-safe.
    private static func randomState() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
