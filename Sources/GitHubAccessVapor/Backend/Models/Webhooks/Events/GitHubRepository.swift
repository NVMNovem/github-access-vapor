//
//  GitHubRepository.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

/// A repository, as it appears inside a webhook payload.
public struct GitHubRepository: Decodable, Sendable {

    public let id: Int64?
    public let name: String?

    /// The `owner/repository` name, which is what a `git clone` URL is built from.
    public let fullName: String
    public let isPrivate: Bool
    public let htmlURL: String?
    public let cloneURL: String?
    public let defaultBranch: String?
    public let owner: GitHubUser?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case isPrivate = "private"
        case htmlURL = "html_url"
        case cloneURL = "clone_url"
        case defaultBranch = "default_branch"
        case owner
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.fullName = try container.decode(String.self, forKey: .fullName)
        self.isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        self.htmlURL = try container.decodeIfPresent(String.self, forKey: .htmlURL)
        self.cloneURL = try container.decodeIfPresent(String.self, forKey: .cloneURL)
        self.defaultBranch = try container.decodeIfPresent(String.self, forKey: .defaultBranch)
        self.owner = try container.decodeIfPresent(GitHubUser.self, forKey: .owner)
    }

    public init(
        id: Int64? = nil,
        name: String? = nil,
        fullName: String,
        isPrivate: Bool = false,
        htmlURL: String? = nil,
        cloneURL: String? = nil,
        defaultBranch: String? = nil,
        owner: GitHubUser? = nil
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.isPrivate = isPrivate
        self.htmlURL = htmlURL
        self.cloneURL = cloneURL
        self.defaultBranch = defaultBranch
        self.owner = owner
    }
}
