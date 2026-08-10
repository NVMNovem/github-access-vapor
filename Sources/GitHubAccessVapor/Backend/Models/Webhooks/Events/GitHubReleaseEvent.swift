//
//  GitHubReleaseEvent.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

/// The payload of a `release` webhook delivery.
///
/// ```swift
/// app.gitHubEvents.on(.release) { event, request in
///     guard event.action == .published else { return }
///     print(event.repository.fullName, event.release.tagName)
/// }
/// ```
public struct GitHubReleaseEvent: GitHubWebhookEvent {

    public static let eventName: GitHubEventName = .release

    /// What happened to the release.
    public let action: Action

    public let release: GitHubRelease
    public let repository: GitHubRepository
    public let sender: GitHubUser?

    /// The installation the delivery was sent on behalf of, when the webhook belongs to a GitHub App.
    ///
    /// This is the identifier to pass to `app.gitHubAccess.installationToken(for:)`.
    public let installation: GitHubInstallationReference?

    /// The `action` field of a `release` payload.
    ///
    /// An open type: GitHub has added actions to this event before, and an unrecognised one must
    /// not turn a delivery into a decoding failure.
    public struct Action: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {

        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: StringLiteralType) {
            self.rawValue = value
        }

        public static let published: Action = "published"
        public static let unpublished: Action = "unpublished"
        public static let created: Action = "created"
        public static let edited: Action = "edited"
        public static let deleted: Action = "deleted"
        public static let prereleased: Action = "prereleased"
        public static let released: Action = "released"
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case release
        case repository
        case sender
        case installation
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.action = try container.decode(Action.self, forKey: .action)
        self.release = try container.decode(GitHubRelease.self, forKey: .release)
        self.repository = try container.decode(GitHubRepository.self, forKey: .repository)
        self.sender = try container.decodeIfPresent(GitHubUser.self, forKey: .sender)
        self.installation = try container.decodeIfPresent(GitHubInstallationReference.self, forKey: .installation)
    }

    public init(
        action: Action,
        release: GitHubRelease,
        repository: GitHubRepository,
        sender: GitHubUser? = nil,
        installation: GitHubInstallationReference? = nil
    ) {
        self.action = action
        self.release = release
        self.repository = repository
        self.sender = sender
        self.installation = installation
    }
}
