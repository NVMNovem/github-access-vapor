//
//  GitHubAccessConfiguration.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

/// Tunables for `app.gitHubAccess`.
public struct GitHubAccessConfiguration: Sendable {

    /// The `User-Agent` used when no other value is configured.
    public static let defaultUserAgent = "GitSyncAccessServer"

    /// The default refresh window: tokens are replaced five minutes before GitHub expires them.
    public static let defaultRefreshLeeway: TimeInterval = 5 * 60

    /// The `User-Agent` GitHub is addressed with.
    ///
    /// GitHub requires every API request to carry one. More than one project uses this package, so
    /// set it to something that identifies yours.
    public var userAgent: String

    /// How long before expiry a cached installation token is replaced.
    ///
    /// Refreshing early keeps a long-running operation from starting with a valid token and
    /// finishing with an expired one.
    public var refreshLeeway: TimeInterval

    /// Where GitHub's REST API lives: `https://api.github.com`, or `https://<host>/api/v3` for
    /// GitHub Enterprise Server. Tests point it at a fake.
    public var apiBaseURL: URL

    public init(
        userAgent: String = GitHubAccessConfiguration.defaultUserAgent,
        refreshLeeway: TimeInterval = GitHubAccessConfiguration.defaultRefreshLeeway,
        apiBaseURL: URL = GitHubAccessConfiguration.defaultAPIBaseURL
    ) {
        self.userAgent = userAgent
        self.refreshLeeway = refreshLeeway
        self.apiBaseURL = apiBaseURL
    }

    /// `https://api.github.com`.
    public static let defaultAPIBaseURL = URL(string: "https://api.github.com")!
}

extension GitHubAccessConfiguration {

    /// `base` joined with `path`, tolerating a trailing slash on the one and a missing leading slash on the other.
    internal static func endpoint(_ base: URL, _ path: String) -> String {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        return root + (path.hasPrefix("/") ? path : "/" + path)
    }
}
