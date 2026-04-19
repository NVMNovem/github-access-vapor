//
//  GitHubAppPayload.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 25/03/2026.
//

import Foundation
import JWTKit

internal struct GitHubAppPayload: JWTPayload {
    
    internal let iss: String
    internal let iat: Int
    internal let exp: Int
    
    internal init(appID: String, now: Date = Date()) {
        let nowSeconds = Int(now.timeIntervalSince1970)
        self.iss = appID
        self.iat = nowSeconds - 60
        self.exp = nowSeconds + (9 * 60)
    }
    
    internal func verify(using signer: some JWTAlgorithm) async throws {
        guard exp > Int(Date().timeIntervalSince1970) else {
            throw JWTError.claimVerificationFailure(failedClaim: nil, reason: "Token expired.")
        }
    }
}
