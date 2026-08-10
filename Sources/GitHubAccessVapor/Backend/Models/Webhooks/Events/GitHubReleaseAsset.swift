//
//  GitHubReleaseAsset.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

/// A file attached to a release.
public struct GitHubReleaseAsset: Decodable, Sendable {

    public let id: Int64?
    public let name: String
    public let label: String?
    public let contentType: String?
    public let size: Int?
    public let browserDownloadURL: String?
    public let url: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case label
        case contentType = "content_type"
        case size
        case browserDownloadURL = "browser_download_url"
        case url
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        self.contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        self.size = try container.decodeIfPresent(Int.self, forKey: .size)
        self.browserDownloadURL = try container.decodeIfPresent(String.self, forKey: .browserDownloadURL)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
    }

    public init(
        id: Int64? = nil,
        name: String,
        label: String? = nil,
        contentType: String? = nil,
        size: Int? = nil,
        browserDownloadURL: String? = nil,
        url: String? = nil
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.contentType = contentType
        self.size = size
        self.browserDownloadURL = browserDownloadURL
        self.url = url
    }
}
