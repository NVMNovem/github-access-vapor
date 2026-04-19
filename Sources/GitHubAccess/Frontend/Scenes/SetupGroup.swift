//
//  SetupGroup.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 17/04/2026.
//

#if canImport(SwiftUI)
import SwiftUI

public struct GitHubSetup: Scene {
    private static let windowId = "setup"
    
    private let setup: ((Result<Int, Error>) -> Void)?
    @State private var incomingURL: URL?
    @State private var setupResult: SetupResult?
    
    public init(setup: @escaping (Result<Int, Error>) -> Void) {
        self.setup = setup
    }
    
    public init() {
        self.setup = nil
    }
    
    public var body: some Scene {
        WindowGroup(id: GitHubSetup.windowId) {
            SetupView(setup, incomingURL: $incomingURL, setupResult: $setupResult, windowId: GitHubSetup.windowId)
                .onOpenURL { url in
                    incomingURL = url
                }
        }
    }
}
#endif
