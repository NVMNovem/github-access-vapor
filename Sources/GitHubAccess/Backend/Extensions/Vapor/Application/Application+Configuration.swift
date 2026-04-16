//
//  Application+Configuration.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 16/04/2026.
//

import Vapor

extension Application {
    
    public func configureAccessServer() async throws {
        middleware.use(FileMiddleware(publicDirectory: directory.publicDirectory))
        
        try await configureRoutes()
    }
}
