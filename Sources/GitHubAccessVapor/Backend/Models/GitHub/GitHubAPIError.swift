import Foundation

/// GitHub answered a REST call with something other than success.
///
/// ``kind`` is what a caller decides on; ``message`` is GitHub's own explanation, which is meant for
/// people and is safe to log. Credentials are never part of it.
public struct GitHubAPIError: Error, Sendable, Equatable, CustomStringConvertible {

    public enum Kind: Sendable, Equatable {
        /// `401`: the App JWT or installation token was refused. For an installation token, the
        /// installation was probably removed; for the App JWT, the credentials are wrong.
        case unauthorized
        /// `403`: authenticated, but not allowed. The App lacks a permission or the installation is suspended.
        case forbidden
        /// `404`: no such installation, repository, release or asset (or the App cannot see it).
        case notFound
        /// `403` or `429` with an exhausted rate limit. `resetAt` is when GitHub says to try again.
        case rateLimited(resetAt: Date?)
        /// `422`: GitHub refused the request body.
        case unprocessable
        /// `5xx`: GitHub's own failure. Worth retrying.
        case server
        /// Any other status.
        case unexpected
    }

    public let kind: Kind
    public let status: UInt
    public let message: String

    public init(kind: Kind, status: UInt, message: String) {
        self.kind = kind
        self.status = status
        self.message = message
    }

    public var description: String { "GitHub answered \(status) (\(kind)): \(message)" }
}
