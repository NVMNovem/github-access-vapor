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

    public init(
        userAgent: String = GitHubAccessConfiguration.defaultUserAgent,
        refreshLeeway: TimeInterval = GitHubAccessConfiguration.defaultRefreshLeeway
    ) {
        self.userAgent = userAgent
        self.refreshLeeway = refreshLeeway
    }
}
