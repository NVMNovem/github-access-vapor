import Foundation

/// A GitHub App's ID and private key, for hosts that hold them somewhere other than environment
/// variables.
///
/// The Manager is the case that needs this: it creates the App through the manifest flow, receives
/// the key from GitHub once, and keeps it in its own secret store. Pass it to
/// `Vapor/Application/GitHubAccess/useCredentials(_:)` and every token, setup check and REST call
/// signs with it. Without a call to that, the credentials are read from `GITHUB_APP_ID` and
/// `GITHUB_PRIVATE_KEY_PATH` / `GITHUB_PRIVATE_KEY` as before.
///
/// Printing one never shows the key.
public struct GitHubAppCredentials: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// The App ID, as GitHub shows it on the App's settings page.
    public let appID: String

    /// The RSA private key in PEM form.
    public let privateKeyPEM: String

    /// - Parameters:
    ///   - appID: The App ID.
    ///   - privateKeyPEM: The PEM. A single line with literal `\n` sequences, which is how secrets
    ///     usually arrive from an environment or a vault, is restored to a multi-line PEM.
    public init(appID: String, privateKeyPEM: String) {
        self.appID = appID
        self.privateKeyPEM = privateKeyPEM.contains("\n")
            ? privateKeyPEM
            : privateKeyPEM.replacingOccurrences(of: "\\n", with: "\n")
    }

    public var description: String { "GitHubAppCredentials(appID: \(appID), privateKey: <redacted>)" }
    public var debugDescription: String { description }
}
