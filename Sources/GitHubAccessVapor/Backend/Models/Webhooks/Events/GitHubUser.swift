//
//  GitHubUser.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

/// An account — a user or an organisation — as it appears inside a webhook payload.
public struct GitHubUser: Decodable, Sendable {

    public let id: Int64?
    public let login: String
    public let type: String?
    public let htmlURL: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case login
        case type
        case htmlURL = "html_url"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.login = try container.decode(String.self, forKey: .login)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.htmlURL = try container.decodeIfPresent(String.self, forKey: .htmlURL)
    }

    public init(
        id: Int64? = nil,
        login: String,
        type: String? = nil,
        htmlURL: String? = nil
    ) {
        self.id = id
        self.login = login
        self.type = type
        self.htmlURL = htmlURL
    }
}
