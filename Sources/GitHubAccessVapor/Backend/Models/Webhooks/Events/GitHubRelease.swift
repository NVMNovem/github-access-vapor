//
//  GitHubRelease.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

/// A release, as it appears inside a webhook payload.
///
/// Only ``tagName`` is required. Everything else is optional or defaulted, so that a payload GitHub
/// has since extended — or trimmed — still decodes.
public struct GitHubRelease: Decodable, Sendable {

    public let id: Int64?
    public let tagName: String
    public let name: String?
    public let body: String?
    public let targetCommitish: String?
    public let draft: Bool
    public let prerelease: Bool
    public let htmlURL: String?
    public let tarballURL: String?
    public let zipballURL: String?
    public let createdAt: Date?
    public let publishedAt: Date?
    public let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case targetCommitish = "target_commitish"
        case draft
        case prerelease
        case htmlURL = "html_url"
        case tarballURL = "tarball_url"
        case zipballURL = "zipball_url"
        case createdAt = "created_at"
        case publishedAt = "published_at"
        case assets
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.tagName = try container.decode(String.self, forKey: .tagName)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.body = try container.decodeIfPresent(String.self, forKey: .body)
        self.targetCommitish = try container.decodeIfPresent(String.self, forKey: .targetCommitish)
        self.draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        self.prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        self.htmlURL = try container.decodeIfPresent(String.self, forKey: .htmlURL)
        self.tarballURL = try container.decodeIfPresent(String.self, forKey: .tarballURL)
        self.zipballURL = try container.decodeIfPresent(String.self, forKey: .zipballURL)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        self.publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        self.assets = try container.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets) ?? []
    }

    public init(
        id: Int64? = nil,
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        targetCommitish: String? = nil,
        draft: Bool = false,
        prerelease: Bool = false,
        htmlURL: String? = nil,
        tarballURL: String? = nil,
        zipballURL: String? = nil,
        createdAt: Date? = nil,
        publishedAt: Date? = nil,
        assets: [GitHubReleaseAsset] = []
    ) {
        self.id = id
        self.tagName = tagName
        self.name = name
        self.body = body
        self.targetCommitish = targetCommitish
        self.draft = draft
        self.prerelease = prerelease
        self.htmlURL = htmlURL
        self.tarballURL = tarballURL
        self.zipballURL = zipballURL
        self.createdAt = createdAt
        self.publishedAt = publishedAt
        self.assets = assets
    }
}
