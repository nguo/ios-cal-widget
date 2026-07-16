import Foundation
import SwiftUI
import GoogleSignIn
import CalCore

/// Wraps GoogleSignIn for the app: interactive sign-in, session restore, and vending a
/// fresh access token for API calls. GoogleSignIn persists its own session in the Keychain,
/// so the app doesn't manually store tokens for its own use. (Sharing the refresh token with
/// the widget extension — for the widget's own refresh — is Milestone 11.)
@MainActor
final class GoogleAuthService: ObservableObject {
    @Published var email: String?
    @Published var isSignedIn = false
    @Published var lastError: String?

    private let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"

    /// Restore a previous session on launch (no UI). Safe to call when not signed in.
    func restore() async {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            apply(user)
        } catch {
            apply(nil) // no previous session — expected on first run
        }
    }

    func signIn() async {
        guard let presenter = Self.topViewController() else {
            lastError = "No presenting view controller."
            return
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: [calendarScope]
            )
            apply(result.user)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        if let email { try? KeychainStore(accessGroup: nil).deleteRefreshToken(accountEmail: email) }
        GIDSignIn.sharedInstance.signOut()
        apply(nil)
    }

    /// A currently-valid access token, refreshing if needed.
    func accessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw AuthError.notSignedIn }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }

    private func apply(_ user: GIDGoogleUser?) {
        email = user?.profile?.email
        isSignedIn = user != nil
        stashCredentials(for: user)
    }

    /// Copy the refresh token + account email into shared storage so the widget's refresh
    /// intent (a separate process) can mint its own access tokens. Uses the default Keychain
    /// access group, which is our shared `keychain-access-groups` entry — readable by both
    /// targets. GoogleSignIn's own session stays where it is; this is a separate copy.
    private func stashCredentials(for user: GIDGoogleUser?) {
        let store = AppGroupStore(suiteName: AppConfig.appGroupID)
        guard let user, let email = user.profile?.email else {
            store?.accountEmail = nil
            return
        }
        store?.accountEmail = email
        try? KeychainStore(accessGroup: nil).saveRefreshToken(user.refreshToken.tokenString, accountEmail: email)
    }

    enum AuthError: LocalizedError {
        case notSignedIn
        var errorDescription: String? { "Not signed in." }
    }

    /// Finds the frontmost view controller to present the Google sign-in sheet from.
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } ?? windows.first }
}
