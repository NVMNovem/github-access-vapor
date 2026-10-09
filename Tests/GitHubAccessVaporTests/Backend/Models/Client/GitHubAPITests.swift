import Crypto
import Foundation
import GitHubAccessModels
import GitHubAccessVapor
import GitHubAccessVaporTesting
import Testing
import Vapor

@testable import GitHubAccessVapor

@Suite("GitHub REST client", .serialized)
struct GitHubAPITests {

    /// Runs `body` against a fake GitHub with the App `424242` and installation `7`.
    private func withGitHub(
        _ body: (Application, FakeGitHub) async throws -> Void
    ) async throws {
        let github = try await FakeGitHub()
        let app = try await Application.make(.testing)
        do {
            app.gitHubAccess.configuration.apiBaseURL = github.baseURL
            await app.gitHubAccess.useCredentials(GitHubAppCredentials(appID: github.appID, privateKeyPEM: TestAppKey.pem))
            github.addInstallation(GitHubInstallation(id: 7), repositories: [GitHubRepositoryRef(fullName: "funico-nv/app")])
            try await body(app, github)
        } catch {
            try? await app.asyncShutdown()
            await github.shutdown()
            throw error
        }
        try await app.asyncShutdown()
        await github.shutdown()
    }

    @Test("the App endpoints are called with a JWT and report the slug")
    func appSlug() async throws {
        try await withGitHub { app, github in
            let slug = try await app.gitHubAccess.appSlug()
            #expect(slug == "funico-server-manager")
            let first = try #require(github.requests.first)
            #expect(first.authorization?.hasPrefix("Bearer ") == true)
            #expect(first.userAgent == app.gitHubAccess.configuration.userAgent)
        }
    }

    @Test("an installation that is not the App's is a not-found error")
    func unknownInstallation() async throws {
        try await withGitHub { app, _ in
            await #expect(throws: GitHubAPIError.self) {
                _ = try await app.gitHubAccess.installation(id: 999)
            }
            let known = try await app.gitHubAccess.installation(id: 7)
            #expect(known.id == 7)
        }
    }

    @Test("installations are followed across pages")
    func paginatesInstallations() async throws {
        try await withGitHub { app, github in
            github.pageSize = 2
            for id in 8...12 { github.addInstallation(GitHubInstallation(id: Int64(id))) }
            let all = try await app.gitHubAccess.installations()
            #expect(all.map(\.id) == [7, 8, 9, 10, 11, 12])
        }
    }

    @Test("repositories come out of GitHub's wrapper object")
    func repositories() async throws {
        try await withGitHub { app, _ in
            let repositories = try await app.gitHubAccess.client(for: 7).repositories()
            #expect(repositories.map(\.fullName) == ["funico-nv/app"])
        }
    }

    @Test("a token GitHub revoked is replaced once, transparently")
    func replacesRevokedToken() async throws {
        try await withGitHub { app, github in
            github.addRelease(GitHubRelease(tagName: "1.0.0"), in: "funico-nv/app")
            let client = app.gitHubAccess.client(for: 7)
            _ = try await client.releases(in: "funico-nv/app")
            let first = try #require(github.issuedTokens.first)
            github.revokeToken(first)
            let releases = try await client.releases(in: "funico-nv/app")
            #expect(releases.map(\.tagName) == ["1.0.0"])
            #expect(github.issuedTokens.count == 2)
        }
    }

    @Test("releases are found by tag and as the latest")
    func releases() async throws {
        try await withGitHub { app, github in
            github.addRelease(GitHubRelease(tagName: "1.0.0"), in: "funico-nv/app")
            github.addRelease(GitHubRelease(tagName: "1.1.0"), in: "funico-nv/app")
            github.addRelease(GitHubRelease(tagName: "2.0.0-beta", prerelease: true), in: "funico-nv/app")
            let client = app.gitHubAccess.client(for: 7)
            let latest = try await client.latestRelease(in: "funico-nv/app")
            let tagged = try await client.release(tag: "1.0.0", in: "funico-nv/app")
            #expect(latest.tagName == "1.1.0")
            #expect(tagged.tagName == "1.0.0")
            await #expect(throws: GitHubAPIError.self) { _ = try await client.release(tag: "9", in: "funico-nv/app") }
        }
    }

    // MARK: Downloads

    private func download(
        _ app: Application, _ github: FakeGitHub, data: Data, publishDigest: Bool = true
    ) async throws -> (GitHubInstallationClient.DownloadedAsset, URL) {
        github.addRelease(GitHubRelease(tagName: "1.0.0"), in: "funico-nv/app")
        let asset = github.addAsset(data, named: "agent", toTag: "1.0.0", in: "funico-nv/app", publishDigest: publishDigest)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let result = try await app.gitHubAccess.client(for: 7).downloadAsset(asset, in: "funico-nv/app", to: destination)
        return (result, destination)
    }

    @Test("an asset is streamed to disk, and the token never reaches the storage host")
    func downloadsAsset() async throws {
        try await withGitHub { app, github in
            let data = Data((0..<200_000).map { UInt8($0 % 251) })
            let (result, destination) = try await download(app, github, data: data)
            defer { try? FileManager.default.removeItem(at: destination) }

            let written = try Data(contentsOf: destination)
            #expect(written == data)
            #expect(result.byteCount == data.count)
            #expect(result.sha256 == SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            #expect(!FileManager.default.fileExists(atPath: destination.path + ".partial"))

            #expect(github.requests.contains { $0.path.contains("/releases/assets/") && $0.authorization != nil })
            let storage = try #require(github.storageRequests.first)
            #expect(storage.authorization == nil)
        }
    }

    @Test("a download that does not match the published digest is refused and leaves nothing")
    func digestMismatch() async throws {
        try await withGitHub { app, github in
            github.addRelease(GitHubRelease(tagName: "1.0.0"), in: "funico-nv/app")
            let real = github.addAsset(Data("real".utf8), named: "agent", toTag: "1.0.0", in: "funico-nv/app")
            var lying = real
            lying.digest = "sha256:" + String(repeating: "0", count: 64)
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            await #expect(throws: Abort.self) {
                _ = try await app.gitHubAccess.client(for: 7).downloadAsset(lying, in: "funico-nv/app", to: destination)
            }
            #expect(!FileManager.default.fileExists(atPath: destination.path))
            #expect(!FileManager.default.fileExists(atPath: destination.path + ".partial"))
        }
    }

    @Test("a cut-short transfer is refused and leaves nothing")
    func truncated() async throws {
        try await withGitHub { app, github in
            github.truncatesDownloads = true
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            github.addRelease(GitHubRelease(tagName: "1.0.0"), in: "funico-nv/app")
            let asset = github.addAsset(Data(repeating: 1, count: 10_000), named: "agent", toTag: "1.0.0", in: "funico-nv/app")
            await #expect(throws: (any Error).self) {
                _ = try await app.gitHubAccess.client(for: 7).downloadAsset(asset, in: "funico-nv/app", to: destination)
            }
            #expect(!FileManager.default.fileExists(atPath: destination.path))
            #expect(!FileManager.default.fileExists(atPath: destination.path + ".partial"))
        }
    }

    @Test("a repository name that is not owner/name is refused before any request")
    func repositoryShape() async throws {
        try await withGitHub { app, github in
            await #expect(throws: (any Error).self) {
                _ = try await app.gitHubAccess.client(for: 7).releases(in: "../orgs/x")
            }
            #expect(github.requests.isEmpty)
        }
    }
}
