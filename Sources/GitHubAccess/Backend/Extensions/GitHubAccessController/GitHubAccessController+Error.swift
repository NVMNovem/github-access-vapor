//
//  GitHubAccessController+Error.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 16/04/2026.
//

extension GitHubAccessController {

    public struct Error: Swift.Error {
        public let status: Status
        public let code: Code
        public let message: String

        public enum Status: String, Sendable {
            case badRequest
            case internalServerError
        }

        public enum Code: String, Sendable {
            case invalidInstallationId = "invalid_installation_id"
        }
    }
}

extension GitHubAccessController.Error {

    public static func badRequest(_ code: Code) -> GitHubAccessController.Error {
        .init(status: .badRequest, code: code, message: code.message)
    }
}

extension GitHubAccessController.Error.Code {

    public var message: String {
        switch self {
        case .invalidInstallationId: "The installation id is invalid."
        }
    }
}
