import Crypto
import Foundation
import GitHubAccessModels
import NIOConcurrencyHelpers
import Vapor

/// A GitHub that runs on `127.0.0.1`, for testing code that talks to GitHub's REST API.
///
/// It is a real HTTP server, not a stubbed client, so everything between your code and the wire is
/// exercised: headers, redirects, streaming, pagination. It serves the endpoints this package and the
/// Manager use (App, installations, installation tokens, repositories, releases, release assets,
/// manifest conversion) and answers the way GitHub does where that matters:
///
/// - the App endpoints need a JWT whose `iss` is ``appID``; the installation endpoints need a token
///   this fake issued, and a revoked one is `401`;
/// - an asset requested as `application/octet-stream` is a `302` to a *second* server (the "CDN"),
///   and ``storageRequests`` records whether an `Authorization` header reached it, which it must not;
/// - listings honour `per_page` and `page` and send a `Link: …; rel="next"` header.
///
/// ```swift
/// let github = try await FakeGitHub()
/// app.gitHubAccess.configuration.apiBaseURL = github.baseURL
/// // … exercise the code, then:
/// await github.shutdown()
/// ```
public final class FakeGitHub: @unchecked Sendable {

    /// What the fake saw.
    public struct RecordedRequest: Sendable, Equatable {
        public let method: String
        public let path: String
        public let query: String
        public let authorization: String?
        public let accept: String?
        public let userAgent: String?
    }

    /// Where to point `GitHubAccessConfiguration.apiBaseURL`.
    public private(set) var baseURL = URL(string: "http://127.0.0.1")!
    /// The App ID the fake expects in a JWT's `iss`.
    public let appID: String

    private let api: Application
    private let storage: Application
    private let lock = NIOLock()
    private var state = State()

    private struct State {
        var appSlug = "funico-server-manager"
        var installations: [Int64: GitHubInstallation] = [:]
        var repositories: [Int64: [GitHubRepositoryRef]] = [:]
        var releases: [String: [GitHubRelease]] = [:]
        var assets: [Int64: Data] = [:]
        var conversions: [String: GitHubAppManifestConversion] = [:]
        var tokens: [String: Int64] = [:]
        var revoked: Set<String> = []
        var issued = 0
        var pageSize = 100
        var truncateDownloads = false
        var requests: [RecordedRequest] = []
        var storageRequests: [RecordedRequest] = []
        var nextAssetID: Int64 = 9_000
    }

    // MARK: Lifecycle

    /// Starts the API and its storage host on free ports.
    public init(appID: String = "424242") async throws {
        self.appID = appID
        let api = try await Application.make(.testing)
        let storage = try await Application.make(.testing)
        api.logger.logLevel = .critical
        storage.logger.logLevel = .critical
        self.api = api
        self.storage = storage

        // Routes first: a Vapor application snapshots its router when the server starts.
        routeStorage()
        try await storage.server.start(address: .hostname("127.0.0.1", port: 0))
        let storageBase = "http://127.0.0.1:\(try Self.port(of: storage))"
        routeAPI(storageBase: storageBase)
        try await api.server.start(address: .hostname("127.0.0.1", port: 0))
        self.baseURL = URL(string: "http://127.0.0.1:\(try Self.port(of: api))")!
    }

    private static func port(of app: Application) throws -> Int {
        guard let port = app.http.server.shared.localAddress?.port else {
            throw Abort(.internalServerError, reason: "The fake GitHub did not bind a port.")
        }
        return port
    }

    /// Stops both servers.
    public func shutdown() async {
        await api.server.shutdown()
        await storage.server.shutdown()
        try? await api.asyncShutdown()
        try? await storage.asyncShutdown()
    }

    // MARK: Scripting

    /// The slug `GET /app` reports.
    public var appSlug: String {
        get { lock.withLock { state.appSlug } }
        set { lock.withLock { state.appSlug = newValue } }
    }

    /// Caps `per_page`, to force pagination with small fixtures.
    public var pageSize: Int {
        get { lock.withLock { state.pageSize } }
        set { lock.withLock { state.pageSize = max(1, newValue) } }
    }

    /// Makes the storage host send half of each asset and then close, like a dropped connection.
    public var truncatesDownloads: Bool {
        get { lock.withLock { state.truncateDownloads } }
        set { lock.withLock { state.truncateDownloads = newValue } }
    }

    public func addInstallation(_ installation: GitHubInstallation, repositories: [GitHubRepositoryRef] = []) {
        lock.withLock {
            state.installations[installation.id] = installation
            state.repositories[installation.id] = repositories
        }
    }

    public func removeInstallation(id: Int64) {
        lock.withLock {
            state.installations[id] = nil
            state.repositories[id] = nil
        }
    }

    /// Adds `release` to `repository` (`owner/name`), newest first.
    public func addRelease(_ release: GitHubRelease, in repository: String) {
        lock.withLock { state.releases[repository, default: []].insert(release, at: 0) }
    }

    /// Attaches an asset with `data` to the release tagged `tag`, with GitHub's `digest` if `publishDigest`.
    @discardableResult
    public func addAsset(
        _ data: Data, named name: String, toTag tag: String, in repository: String, publishDigest: Bool = true
    ) -> GitHubReleaseAsset {
        lock.withLock {
            state.nextAssetID += 1
            let id = state.nextAssetID
            let digest = publishDigest ? "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() : nil
            let asset = GitHubReleaseAsset(
                id: id, name: name, contentType: "application/octet-stream", size: data.count, digest: digest
            )
            state.assets[id] = data
            if let index = state.releases[repository]?.firstIndex(where: { $0.tagName == tag }) {
                state.releases[repository]?[index].assets.append(asset)
            }
            return asset
        }
    }

    /// What `POST /app-manifests/<code>/conversions` returns for `code`, once.
    public func addManifestConversion(code: String, _ conversion: GitHubAppManifestConversion) {
        lock.withLock { state.conversions[code] = conversion }
    }

    /// Makes `token` fail with `401` from now on, like a token for an installation that was removed.
    public func revokeToken(_ token: String) {
        lock.withLock { _ = state.revoked.insert(token) }
    }

    /// Every installation token issued so far.
    public var issuedTokens: [String] { lock.withLock { Array(state.tokens.keys).sorted() } }

    /// Requests to the API host, oldest first.
    public var requests: [RecordedRequest] { lock.withLock { state.requests } }

    /// Requests to the storage host, oldest first.
    public var storageRequests: [RecordedRequest] { lock.withLock { state.storageRequests } }

    // MARK: Routes

    private func record(_ request: Request, storage: Bool = false) {
        let recorded = RecordedRequest(
            method: request.method.rawValue, path: request.url.path, query: request.url.query ?? "",
            authorization: request.headers.first(name: .authorization), accept: request.headers.first(name: .accept),
            userAgent: request.headers.first(name: .userAgent)
        )
        lock.withLock {
            if storage { state.storageRequests.append(recorded) } else { state.requests.append(recorded) }
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private func json(_ value: some Encodable, status: HTTPStatus = .ok, headers: HTTPHeaders = [:]) throws -> Response {
        var headers = headers
        headers.contentType = .json
        return Response(status: status, headers: headers, body: .init(data: try Self.encoder.encode(value)))
    }

    private func message(_ text: String, _ status: HTTPStatus) throws -> Response {
        try json(["message": text], status: status)
    }

    private enum Caller {
        case installation(Int64)
        case refused(Response)
    }

    /// The installation an `Authorization: Bearer ghs_…` header belongs to, or a `401`.
    private func installation(for request: Request) -> Caller {
        guard let token = request.headers.bearerAuthorization?.token else {
            return .refused((try? message("Requires authentication", .unauthorized)) ?? Response(status: .unauthorized))
        }
        let id: Int64? = lock.withLock { state.revoked.contains(token) ? nil : state.tokens[token] }
        guard let id else {
            return .refused((try? message("Bad credentials", .unauthorized)) ?? Response(status: .unauthorized))
        }
        return .installation(id)
    }

    /// Whether the request carries a JWT issued for this App.
    private func isAppJWT(_ request: Request) -> Bool {
        guard let token = request.headers.bearerAuthorization?.token else { return false }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return "\(object["iss"] ?? "")" == appID
    }

    /// A page of `items` with GitHub's `Link` header, honouring `per_page` and `page`.
    private func page<T: Encodable>(_ items: [T], for request: Request, wrap: ((([T]), Int) -> any Encodable)? = nil) throws -> Response {
        let cap = lock.withLock { state.pageSize }
        let perPage = min(request.query[Int.self, at: "per_page"] ?? 30, cap)
        let page = max(1, request.query[Int.self, at: "page"] ?? 1)
        let start = (page - 1) * perPage
        let slice = start < items.count ? Array(items[start..<min(items.count, start + perPage)]) : []
        var headers = HTTPHeaders()
        if start + perPage < items.count {
            var components = URLComponents(string: "http://\(request.headers.first(name: .host) ?? "127.0.0.1")\(request.url.path)")!
            components.queryItems = [.init(name: "per_page", value: String(perPage)), .init(name: "page", value: String(page + 1))]
            headers.add(name: .link, value: "<\(components.string!)>; rel=\"next\"")
        }
        if let wrap { return try json(AnyEncodable(wrap(slice, items.count)), headers: headers) }
        return try json(slice, headers: headers)
    }

    private func routeAPI(storageBase: String) {
        api.get("app") { [self] request -> Response in
            record(request)
            guard isAppJWT(request) else { return try message("A JSON web token could not be decoded", .unauthorized) }
            struct AppRecord: Encodable { var id: Int; var slug: String; var name: String }
            return try json(AppRecord(id: Int(appID) ?? 0, slug: appSlug, name: "Funico Server Manager"))
        }

        api.get("app", "installations") { [self] request -> Response in
            record(request)
            guard isAppJWT(request) else { return try message("A JSON web token could not be decoded", .unauthorized) }
            let all = lock.withLock { state.installations.values.sorted { $0.id < $1.id } }
            return try page(all, for: request)
        }

        api.get("app", "installations", ":id") { [self] request -> Response in
            record(request)
            guard isAppJWT(request) else { return try message("A JSON web token could not be decoded", .unauthorized) }
            guard let id = request.parameters.get("id", as: Int64.self),
                  let installation = lock.withLock({ state.installations[id] }) else { return try message("Not Found", .notFound) }
            return try json(installation)
        }

        api.post("app", "installations", ":id", "access_tokens") { [self] request -> Response in
            record(request)
            guard isAppJWT(request) else { return try message("A JSON web token could not be decoded", .unauthorized) }
            guard let id = request.parameters.get("id", as: Int64.self),
                  lock.withLock({ state.installations[id] != nil }) else { return try message("Not Found", .notFound) }
            let token: String = lock.withLock {
                state.issued += 1
                let token = "ghs_fake_\(id)_\(state.issued)"
                state.tokens[token] = id
                return token
            }
            struct Issued: Encodable { var token: String; var expires_at: Date }
            return try json(Issued(token: token, expires_at: Date().addingTimeInterval(3_600)), status: .created)
        }

        api.get("installation", "repositories") { [self] request -> Response in
            record(request)
            switch installation(for: request) {
            case .refused(let response): return response
            case .installation(let id):
                let repositories = lock.withLock { state.repositories[id] ?? [] }
                struct Wrapper: Encodable { var total_count: Int; var repositories: [GitHubRepositoryRef] }
                return try page(repositories, for: request) { slice, total in Wrapper(total_count: total, repositories: slice) }
            }
        }

        api.get("repos", ":owner", ":repo", "releases") { [self] request -> Response in
            record(request)
            if case .refused(let response) = installation(for: request) { return response }
            let repository = "\(request.parameters.get("owner") ?? "")/\(request.parameters.get("repo") ?? "")"
            guard let releases = lock.withLock({ state.releases[repository] }) else { return try message("Not Found", .notFound) }
            return try page(releases, for: request)
        }

        api.get("repos", ":owner", ":repo", "releases", "latest") { [self] request -> Response in
            record(request)
            if case .refused(let response) = installation(for: request) { return response }
            let repository = "\(request.parameters.get("owner") ?? "")/\(request.parameters.get("repo") ?? "")"
            guard let release = lock.withLock({ state.releases[repository]?.first { !$0.draft && !$0.prerelease } }) else {
                return try message("Not Found", .notFound)
            }
            return try json(release)
        }

        api.get("repos", ":owner", ":repo", "releases", "tags", ":tag") { [self] request -> Response in
            record(request)
            if case .refused(let response) = installation(for: request) { return response }
            let repository = "\(request.parameters.get("owner") ?? "")/\(request.parameters.get("repo") ?? "")"
            let tag = request.parameters.get("tag") ?? ""
            guard let release = lock.withLock({ state.releases[repository]?.first { $0.tagName == tag } }) else {
                return try message("Not Found", .notFound)
            }
            return try json(release)
        }

        api.get("repos", ":owner", ":repo", "releases", "assets", ":id") { [self] request -> Response in
            record(request)
            if case .refused(let response) = installation(for: request) { return response }
            guard let id = request.parameters.get("id", as: Int64.self), lock.withLock({ state.assets[id] != nil }) else {
                return try message("Not Found", .notFound)
            }
            guard request.headers.first(name: .accept)?.contains("application/octet-stream") == true else {
                return try message("The fake serves assets only as application/octet-stream", .notAcceptable)
            }
            let response = Response(status: .found)
            response.headers.replaceOrAdd(name: .location, value: "\(storageBase)/asset/\(id)?sig=fake")
            return response
        }

        api.post("app-manifests", ":code", "conversions") { [self] request -> Response in
            record(request)
            let code = request.parameters.get("code") ?? ""
            guard let conversion = lock.withLock({ state.conversions.removeValue(forKey: code) }) else {
                return try message("Not Found", .notFound)
            }
            return try json(conversion, status: .created)
        }
    }

    private func routeStorage() {
        storage.get("asset", ":id") { [self] request -> Response in
            record(request, storage: true)
            guard let id = request.parameters.get("id", as: Int64.self), let data = lock.withLock({ state.assets[id] }) else {
                return Response(status: .notFound)
            }
            let truncate = lock.withLock { state.truncateDownloads }
            var headers = HTTPHeaders()
            headers.contentType = .binary
            // Declaring the full length and sending half is what a dropped connection looks like.
            headers.replaceOrAdd(name: .contentLength, value: String(data.count))
            let body = truncate ? data.prefix(data.count / 2) : data
            let response = Response(status: .ok, headers: headers, body: .init(data: Data(body)))
            return response
        }
    }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
}
