import AsyncHTTPClient
import Crypto
import Foundation
import GitHubAccessModels
import NIOCore
import NIOFoundationCompat
import Vapor

/// REST access to GitHub as one installation of the App. Obtain it from
/// ``Vapor/Application/GitHubAccess/client(for:)``.
///
/// ```swift
/// let github = app.gitHubAccess.client(for: installationID)
/// let release = try await github.release(tag: "v1.4.0", in: "Funico-NV/funico-invoices-service")
/// ```
///
/// A repository is always `"owner/name"`. Anything else is refused before a request is made, so a
/// value that came from a user cannot steer the call to a different path.
public struct GitHubInstallationClient: Sendable {

    public let installationID: Int64
    internal let api: GitHubAPI

    internal init(installationID: Int64, api: GitHubAPI) {
        self.installationID = installationID
        self.api = api
    }

    // MARK: Repositories

    /// The repositories this installation can see.
    public func repositories() async throws -> [GitHubRepositoryRef] {
        struct Page: Decodable, Sendable { var repositories: [GitHubRepositoryRef] }
        return try await api.pages(Page.self, "/installation/repositories", auth: .installation(installationID)) { $0.repositories }
    }

    // MARK: Releases

    /// Releases of `repository`, newest first. Draft releases appear only if the App may see them.
    public func releases(in repository: String) async throws -> [GitHubRelease] {
        let path = try Self.repositoryPath(repository)
        return try await api.pages([GitHubRelease].self, "\(path)/releases", auth: .installation(installationID)) { $0 }
    }

    /// The release tagged `tag`.
    ///
    /// - Throws: ``GitHubAPIError`` with kind `.notFound` if there is none.
    public func release(tag: String, in repository: String) async throws -> GitHubRelease {
        let path = try Self.repositoryPath(repository)
        return try await api.json(GitHubRelease.self, .GET, "\(path)/releases/tags/\(Self.segment(tag))", auth: .installation(installationID))
    }

    /// The most recent published, non-prerelease release.
    public func latestRelease(in repository: String) async throws -> GitHubRelease {
        let path = try Self.repositoryPath(repository)
        return try await api.json(GitHubRelease.self, .GET, "\(path)/releases/latest", auth: .installation(installationID))
    }

    // MARK: Assets

    /// What a finished download amounts to.
    public struct DownloadedAsset: Sendable, Equatable {
        public let url: URL
        public let byteCount: Int
        /// Lowercase hex SHA-256 of the bytes written, computed while streaming.
        public let sha256: String
    }

    /// Streams a release asset to `destination`.
    ///
    /// The bytes are never held in memory: a static server binary is tens of megabytes. They are
    /// written to `destination` + `.partial` and moved into place only when the transfer is complete,
    /// so a crash or a cut connection never leaves something that looks like the asset.
    ///
    /// GitHub answers the API request with a redirect to a signed storage URL. It is followed, and the
    /// installation token is **not** sent to the storage host (the HTTP client drops `Authorization`
    /// when the origin changes), which is what keeps a short-lived credential out of a third party's logs.
    ///
    /// The result is checked before it is accepted: the byte count against `asset.size`, and the
    /// SHA-256 against `asset.digest` when GitHub provided one.
    ///
    /// - Throws: ``GitHubAPIError``, or an ``Abort`` with `502` if the transfer was cut short or did
    ///   not match what GitHub described.
    public func downloadAsset(_ asset: GitHubReleaseAsset, in repository: String, to destination: URL) async throws -> DownloadedAsset {
        guard let assetID = asset.id else { throw Abort(.badRequest, reason: "The release asset has no ID.") }
        let path = try Self.repositoryPath(repository)
        let application = api.application
        let configuration = application.gitHubAccess.configuration
        let token = try await application.gitHubAccess.installationToken(for: installationID).token

        var request = HTTPClientRequest(url: GitHubAccessConfiguration.endpoint(configuration.apiBaseURL, "\(path)/releases/assets/\(assetID)"))
        request.headers.add(name: "Authorization", value: "Bearer \(token)")
        request.headers.add(name: "Accept", value: "application/octet-stream")
        request.headers.add(name: "User-Agent", value: configuration.userAgent)
        request.headers.add(name: "X-GitHub-Api-Version", value: GitHubAPI.apiVersion)

        let response = try await application.http.client.shared.execute(request, timeout: .seconds(60))
        guard response.status == .ok else {
            var failure = ClientResponse(status: response.status, headers: response.headers)
            failure.body = try? await response.body.collect(upTo: 64 * 1024)
            throw GitHubAPI.error(from: failure)
        }

        let partial = destination.appendingPathExtension("partial")
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let handle = try FileHandle(forWritingTo: partial)
        var hasher = SHA256()
        var count = 0
        do {
            for try await chunk in response.body {
                let data = Data(buffer: chunk)
                hasher.update(data: data)
                count += data.count
                try handle.write(contentsOf: data)
            }
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: partial)
            throw error
        }

        let sha256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        if let expected = asset.size, expected != count {
            try? FileManager.default.removeItem(at: partial)
            throw Abort(.badGateway, reason: "The download was cut short: \(count) of \(expected) bytes.")
        }
        if let digest = asset.digest, digest.hasPrefix("sha256:"), digest.dropFirst(7).lowercased() != sha256 {
            try? FileManager.default.removeItem(at: partial)
            throw Abort(.badGateway, reason: "The download does not match the digest GitHub published.")
        }

        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        return DownloadedAsset(url: destination, byteCount: count, sha256: sha256)
    }

    // MARK: Paths

    /// `/repos/<owner>/<name>`, or an error for anything that is not exactly that shape.
    internal static func repositoryPath(_ repository: String) throws -> String {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard parts.count == 2, parts.allSatisfy({ part in
            !part.isEmpty && part != "." && part != ".." && part.unicodeScalars.allSatisfy(allowed.contains)
        }) else {
            throw Abort(.badRequest, reason: "A repository is written owner/name.")
        }
        return "/repos/\(parts[0])/\(parts[1])"
    }

    /// One path segment, percent-encoded so a tag like `release/1.0` cannot add segments.
    internal static func segment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? ""
    }
}
