//
//  GitHubInstallationToken.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 25/03/2026.
//

import Foundation

public struct GitHubInstallationToken: Decodable {
    
    public let token: String
    public let expiresAt: Date
    
    public enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }
}

extension GitHubInstallationToken: Sendable {}
