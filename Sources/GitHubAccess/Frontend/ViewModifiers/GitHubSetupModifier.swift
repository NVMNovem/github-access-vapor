//
//  GitHubSetupModifier.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 19/04/2026.
//

#if canImport(SwiftUI)
import SwiftUI

struct GitHubSetupModifier: ViewModifier {
    
    private let setup: ((Result<Int, Error>) -> Void)?
    
    @State private var incomingURL: URL?
    @State private var setupResult: SetupResult?
    
    @State private var isPresented: Bool = false
    
    init(setup: ((Result<Int, Error>) -> Void)?, incomingURL: URL? = nil, setupResult: SetupResult? = nil) {
        self.setup = setup
        self.incomingURL = incomingURL
        self.setupResult = setupResult
    }
    
    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                incomingURL = url
                isPresented = true
            }
            .sheet(isPresented: $isPresented, onDismiss: {
                incomingURL = nil
                setupResult = nil
            }) {
                if #available(macOS 15.0, *) {
                    NavigationStack {
                        SetupView(setup, incomingURL: $incomingURL, setupResult: $setupResult)
                            .frame(
                                minWidth: 420, idealWidth: 480, maxWidth: 520,
                                minHeight: 220, idealHeight: 280, maxHeight: 360
                            )
                    }
                    .presentationSizing(.fitted)
                } else {
                    NavigationStack {
                        SetupView(setup, incomingURL: $incomingURL, setupResult: $setupResult)
                            .frame(
                                minWidth: 420, idealWidth: 480, maxWidth: 520,
                                minHeight: 220, idealHeight: 280, maxHeight: 360
                            )
                    }
                }
            }
    }
}

extension View {
    
    /// > Important: ``DocumentGroup`` scenes ignore the URL handling. Instead,
    ///   document scenes decide whether to open a new scene to handle an
    ///   external event by comparing the incoming URL or user activity's
    ///   <doc://com.apple.documentation/documentation/Foundation/NSUserActivity/1418086-webpageurl>
    ///   against the document group's supported types.
    ///   Use the ``GitHubSetup`` scene when working with ``DocumentGroup`` scenes instead.
    ///
    public func gitHubSetup(setup: @escaping (Result<Int, Error>) -> Void) -> some View {
        self.modifier(GitHubSetupModifier(setup: setup))
    }
}
#endif
