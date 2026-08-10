//
//  GitHubInstallationReference.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 10/08/2026.
//

import Foundation

/// The `installation` object GitHub attaches to App webhook deliveries.
///
/// Its ``id`` is what `app.gitHubAccess.installationToken(for:)` takes, so a delivery carries
/// everything needed to clone the repository it describes.
public struct GitHubInstallationReference: Decodable, Sendable {

    public let id: Int64
    public let nodeID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case nodeID = "node_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(Int64.self, forKey: .id)
        self.nodeID = try container.decodeIfPresent(String.self, forKey: .nodeID)
    }

    public init(id: Int64, nodeID: String? = nil) {
        self.id = id
        self.nodeID = nodeID
    }
}
