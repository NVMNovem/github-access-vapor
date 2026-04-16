//
//  CreateGitHubToken+Validation.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 16/04/2026.
//

extension Components.Schemas.CreateGitHubToken {
    
    func validated(_ keyPath: KeyPath<Self, Int64>) throws -> Int64 {
        let value = self[keyPath: keyPath]
        
        switch keyPath {
        case \Self.installationId:
            let installationId = value
            
            return installationId
        default:
            return value
        }
    }
}
