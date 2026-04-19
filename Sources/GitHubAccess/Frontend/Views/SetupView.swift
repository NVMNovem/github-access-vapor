//
//  SetupView.swift
//  github-access-vapor
//
//  Created by Damian Van de Kauter on 19/04/2026.
//

#if canImport(SwiftUI)
import SwiftUI

internal struct SetupView: View {
    
    private let windowId: String?
    
    private let setup: ((SetupResult) -> Void)?
    @Binding private var incomingURL: URL?
    @Binding private var setupResult: SetupResult?
    
    @State private var setupFinished: Bool = false
    @State private var setupLoaded: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    
    internal init(
        _ setup: ((SetupResult) -> Void)?,
        incomingURL: Binding<URL?>,
        setupResult: Binding<SetupResult?> = .constant(nil),
        windowId: String,
    ) {
        self.windowId = windowId
        self.setup = setup
        self._incomingURL = incomingURL
        self._setupResult = setupResult
    }
    
    internal init(
        _ setup: ((SetupResult) -> Void)?,
        incomingURL: Binding<URL?>,
        setupResult: Binding<SetupResult?> = .constant(nil)
    ) {
        self.windowId = nil
        self.setup = setup
        self._incomingURL = incomingURL
        self._setupResult = setupResult
    }
    
    internal var body: some View {
        VStack {
            switch setupResult {
            case .success:
                Image(systemName: setupLoaded ? "checkmark.seal" : "seal")
                    .symbolVariant(.fill)
                    .foregroundStyle(Color.green)
                    .font(.system(size: 100))
                    .contentTransition(.symbolEffect(.replace))
                    .padding()
                    .task {
                        try? await Task.sleep(for: .seconds(0.1))
                        await MainActor.run {
                            withAnimation {
                                self.setupLoaded = true
                            }
                        }
                    }
            default:
                ProgressView {
                    Text("Setting up...")
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: 300)
                .padding(.horizontal)
            }
            if setupFinished {
                Button("Close") {
                    close()
                }
            }
        }
        .toolbar {
            if setupFinished {
                ToolbarItem {
                    Button("Close") {
                        close()
                    }
                }
            }
        }
        .onChange(of: incomingURL, initial: true) { _, newURL in
            guard let newURL, setupResult == nil else { return }
            
            Task {
                do {
                    let installationId = try extractInstallationId(from: newURL)
                    try await Task.sleep(for: .seconds(2.5))
                    
                    let result: SetupResult = .success(installationId)
                    self.setupResult = result
                    setup?(result)
                    
                    await initiateClose()
                } catch {
                    let result: SetupResult = .failure(error)
                    self.setupResult = result
                    setup?(result)
                }
            }
        }
    }
    
    private func initiateClose() async {
        do {
            try await Task.sleep(for: .seconds(2.5))
        } catch {
            print("[GitHub Access] Failed to sleep", error, separator: ": ")
            print("[GitHub Access] Will try to close the window either way...")
        }
        
        await MainActor.run {
            close()
            withAnimation {
                self.setupFinished = true
            }
        }
    }
    
    @MainActor
    private func close() {
        dismiss()
    
        if let windowId {
            dismissWindow(id: windowId)
        }
    }
    
    private func extractInstallationId(from url: URL) throws(SetupError) -> Int {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let installationIdString = components.queryItems?.first(where: { $0.name == "installation_id" })?.value,
              let installationId = Int(installationIdString) else {
            throw SetupError.invalidInstallationID
        }
        
        return installationId
    }
}
#endif
