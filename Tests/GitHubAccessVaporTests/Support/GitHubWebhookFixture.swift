//
//  GitHubWebhookFixture.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

import Vapor
import GitHubAccessVaporTesting

internal enum GitHubWebhookFixture {

    internal static let secret = "test-secret"
    internal static let path = "/github/webhook"

    /// A `release.published` payload written the way GitHub actually sends one: pretty-printed,
    /// with its own key order, an escaped non-ASCII character, and a field this package does not
    /// model.
    ///
    /// Deliberately *not* canonical JSON. Encoding the decoded form of this payload produces
    /// different bytes, which is exactly what breaks signature verification when a webhook route
    /// verifies anything other than the body it received.
    internal static let releasePublished = Data("""
    {
      "action" : "published",
      "release" : {
        "id" : 900,
        "tag_name" : "1.4.0",
        "name" : "Release caf\\u00e9 1.4.0",
        "draft" : false,
        "prerelease" : false,
        "html_url" : "https://github.com/octocat/hello-world/releases/tag/1.4.0",
        "published_at" : "2026-08-10T09:15:30Z",
        "assets" : []
      },
      "repository" : {
        "id" : 42,
        "name" : "hello-world",
        "full_name" : "octocat/hello-world",
        "private" : true,
        "default_branch" : "main"
      },
      "installation" : { "id" : 12345678 },
      "sender" : { "id" : 7, "login" : "octocat" },
      "a_field_github_added_after_this_package_shipped" : { "nested" : [1, 2, 3] }
    }
    """.utf8)

    /// The same payload re-encoded from its decoded form: semantically identical, byte-different.
    internal static func canonicalised(_ payload: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: payload)

        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    internal static func headers(
        body: Data,
        secret: String = GitHubWebhookFixture.secret,
        event: String = "release",
        deliveryID: String = UUID().uuidString,
        signature: String? = nil
    ) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.contentType = .json

        if let signature {
            headers.add(name: GitHubWebhookSigner.headerName, value: signature)
        } else {
            headers.add(
                name: GitHubWebhookSigner.headerName,
                value: GitHubWebhookSigner.sign(body: body, secret: secret)
            )
        }

        headers.add(name: "X-GitHub-Event", value: event)
        headers.add(name: "X-GitHub-Delivery", value: deliveryID)

        return headers
    }
}
