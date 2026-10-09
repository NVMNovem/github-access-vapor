import Foundation
import NIOCore
import NIOHTTP1
import Vapor

/// The REST calls this package makes to GitHub, with the authentication, headers, pagination and
/// error mapping they share.
///
/// Everything goes through `app.client`, so a host's (or a test's) own `Client` is honoured, and
/// through ``GitHubAccessConfiguration/apiBaseURL``, so GitHub Enterprise Server and fakes work.
internal struct GitHubAPI: Sendable {

    internal enum Auth: Sendable {
        /// No credentials (the manifest conversion is authenticated by the code in its URL).
        case none
        /// As the App itself: JWT.
        case app
        /// As an installation: its cached token, replaced once if GitHub refuses it.
        case installation(Int64)
    }

    internal static let apiVersion = "2026-03-10"
    /// A listing longer than this many pages is cut short rather than followed forever.
    internal static let maxPages = 20

    internal let application: Application

    internal var access: Application.GitHubAccess { application.gitHubAccess }

    internal init(_ application: Application) { self.application = application }

    // MARK: Requests

    internal func send(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String] = [:],
        auth: Auth,
        accept: String = "application/vnd.github+json",
        body: (any Encodable & Sendable)? = nil,
        followingRedirects: Bool = true
    ) async throws -> ClientResponse {
        let response = try await perform(method, urlString(path, query: query), auth: auth, accept: accept, body: body, token: nil)
        guard response.status == .unauthorized, case .installation(let id) = auth else { return response }

        // The cached token can be revoked before it expires (the installation was removed and added
        // back). One fresh token and one retry; a second refusal is real.
        let fresh = try await access.refreshInstallationToken(for: id)
        return try await perform(method, urlString(path, query: query), auth: auth, accept: accept, body: body, token: fresh.token)
    }

    /// A request whose success body is decoded as `T`.
    internal func json<T: Decodable & Sendable>(
        _ type: T.Type,
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String] = [:],
        auth: Auth,
        body: (any Encodable & Sendable)? = nil,
        success: Set<HTTPResponseStatus> = [.ok]
    ) async throws -> T {
        let response = try await send(method, path, query: query, auth: auth, body: body)
        try check(response, success: success)
        return try decode(T.self, from: response)
    }

    /// Every item of a listing, following `Link: <…>; rel="next"`.
    ///
    /// - Parameter items: Picks the array out of one page's body: the page itself for most
    ///   endpoints, a wrapper's field (`repositories`) for others.
    internal func pages<Page: Decodable & Sendable, Item: Sendable>(
        _ page: Page.Type,
        _ path: String,
        query: [String: String] = [:],
        auth: Auth,
        items: @Sendable (Page) -> [Item]
    ) async throws -> [Item] {
        var result: [Item] = []
        var next: String? = urlString(path, query: query.merging(["per_page": "100"]) { current, _ in current })
        var count = 0
        while let url = next, count < Self.maxPages {
            count += 1
            var response = try await perform(.GET, url, auth: auth, accept: "application/vnd.github+json", body: nil, token: nil)
            if response.status == .unauthorized, case .installation(let id) = auth {
                let fresh = try await access.refreshInstallationToken(for: id)
                response = try await perform(.GET, url, auth: auth, accept: "application/vnd.github+json", body: nil, token: fresh.token)
            }
            try check(response, success: [.ok])
            result += items(try decode(Page.self, from: response))
            next = Self.nextLink(in: response.headers)
        }
        return result
    }

    // MARK: Plumbing

    private func urlString(_ path: String, query: [String: String]) -> String {
        let base = GitHubAccessConfiguration.endpoint(access.configuration.apiBaseURL, path)
        guard !query.isEmpty, var components = URLComponents(string: base) else { return base }
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.string ?? base
    }

    private func perform(
        _ method: HTTPMethod, _ url: String, auth: Auth, accept: String, body: (any Encodable & Sendable)?, token: String?
    ) async throws -> ClientResponse {
        let configuration = access.configuration
        let bearer: String?
        switch auth {
        case .none: bearer = nil
        case .app: bearer = try await access.appJWT()
        case .installation(let id):
            if let token { bearer = token } else { bearer = try await access.installationToken(for: id).token }
        }

        var headers = HTTPHeaders()
        if let bearer { headers.bearerAuthorization = .init(token: bearer) }
        headers.add(name: .accept, value: accept)
        headers.add(name: .userAgent, value: configuration.userAgent)
        headers.add(name: .init("X-GitHub-Api-Version"), value: Self.apiVersion)

        var request = ClientRequest(method: method, url: URI(string: url), headers: headers)
        if let body {
            request.headers.contentType = .json
            request.body = ByteBuffer(data: try JSONEncoder().encode(AnyEncodable(body)))
        }
        return try await application.client.send(request)
    }

    /// Throws ``GitHubAPIError`` unless the response is one of `success`.
    internal func check(_ response: ClientResponse, success: Set<HTTPResponseStatus>) throws {
        guard !success.contains(response.status) else { return }
        throw Self.error(from: response)
    }

    internal static func error(from response: ClientResponse) -> GitHubAPIError {
        struct Body: Decodable { var message: String? }
        let text = response.body.flatMap { buffer in
            (try? JSONDecoder().decode(Body.self, from: Data(buffer: buffer)))?.message
        } ?? "No explanation"
        let message = String(text.prefix(300))
        let status = response.status.code

        let remaining = response.headers.first(name: "X-RateLimit-Remaining")
        let reset = response.headers.first(name: "X-RateLimit-Reset").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        let kind: GitHubAPIError.Kind
        switch response.status.code {
        case 429: kind = .rateLimited(resetAt: reset)
        case 403 where remaining == "0": kind = .rateLimited(resetAt: reset)
        case 401: kind = .unauthorized
        case 403: kind = .forbidden
        case 404: kind = .notFound
        case 422: kind = .unprocessable
        case 500...599: kind = .server
        default: kind = .unexpected
        }
        return GitHubAPIError(kind: kind, status: UInt(status), message: message)
    }

    internal func decode<T: Decodable>(_ type: T.Type, from response: ClientResponse) throws -> T {
        guard let body = response.body else {
            throw Abort(.badGateway, reason: "GitHub sent no body where one was expected.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: Data(buffer: body))
        } catch {
            application.logger.error("GitHub answered something this version cannot read: \(error)")
            throw Abort(.badGateway, reason: "GitHub's answer could not be read.")
        }
    }

    internal static func nextLink(in headers: HTTPHeaders) -> String? {
        for header in headers[.link] {
            for part in header.split(separator: ",") where part.contains("rel=\"next\"") {
                guard let start = part.firstIndex(of: "<"), let end = part.firstIndex(of: ">"), start < end else { continue }
                return String(part[part.index(after: start)..<end])
            }
        }
        return nil
    }
}

/// Lets a heterogeneous `Encodable` go through `JSONEncoder.encode`.
private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
}
