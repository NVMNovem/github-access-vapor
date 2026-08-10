//
//  GitHubEventName.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

/// The value GitHub sends in the `X-GitHub-Event` header.
///
/// Deliberately an open type rather than an enum: GitHub adds event types over time, and a delivery
/// this package does not know about must still reach ``GitHubEventDispatcher/onAnyEvent(use:)``
/// instead of failing to decode.
///
/// ```swift
/// let workflowRun: GitHubEventName = "workflow_run"
/// ```
public struct GitHubEventName: RawRepresentable, Hashable, Sendable, Codable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension GitHubEventName: ExpressibleByStringLiteral {

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

extension GitHubEventName: CustomStringConvertible {

    public var description: String { rawValue }
}

extension GitHubEventName {

    /// A release was published, edited, deleted, or otherwise changed.
    public static let release: GitHubEventName = "release"

    /// Sent once when a webhook is created, to confirm it is reachable.
    public static let ping: GitHubEventName = "ping"
}
