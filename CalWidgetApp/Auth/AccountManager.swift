import Foundation
import SwiftUI
import GoogleSignIn
import CalCore

/// Owns the set of signed-in Google accounts.
///
/// GoogleSignIn is used only to *acquire* credentials: it holds one session at a time and
/// `restorePreviousSignIn` restores one account, so it can't represent "three accounts are signed
/// in". What it can do is present the chooser once per account and hand back a refresh token,
/// which goes into the shared Keychain under that email. From then on every token — app and
/// extension alike — is minted by `TokenRefreshService` from that stored token, so there is one
/// credential path instead of two, and the app no longer needs a live session to sync.
///
/// The authority on "am I signed in" is therefore `AppGroupStore.accountEmails`, not the SDK.
@MainActor
final class AccountManager: ObservableObject {
    @Published private(set) var accounts: [String] = []
    @Published var lastError: String?

    private let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"
    private var store: AppGroupStore? { AppGroupStore(suiteName: AppConfig.appGroupID) }

    init() {
        accounts = store?.accountEmails ?? []
    }

    var isSignedIn: Bool { !accounts.isEmpty }

    /// Presents the Google chooser and adds whichever account the user picks. Adding an account
    /// they already added just refreshes its stored token.
    func addAccount() async {
        guard let presenter = Self.topViewController() else {
            lastError = "No presenting view controller."
            return
        }
        do {
            // Sign the SDK out first so it always shows the chooser rather than silently reusing
            // the last session — otherwise "Add account" would re-add the account you already have.
            GIDSignIn.sharedInstance.signOut()
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: [calendarScope]
            )
            guard let email = result.user.profile?.email else {
                lastError = "Google returned no account email."
                return
            }
            try KeychainStore(accessGroup: nil)
                .saveRefreshToken(result.user.refreshToken.tokenString, accountEmail: email)
            // Drop the SDK session now that the refresh token is stored. It stays valid
            // server-side, and keeping the session would only make the *next* add skip the
            // chooser. Nothing else reads it.
            GIDSignIn.sharedInstance.signOut()

            if !accounts.contains(email) { accounts.append(email) }
            store?.accountEmails = accounts
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Forgets an account: its token, its registry entry, its calendars, and its events.
    ///
    /// The cached events have to go too. Widgets that selected them would otherwise keep rendering
    /// a removed account's meetings until the next sync happened to overwrite the file — and a
    /// widget selecting *only* removed calendars would never trigger one.
    func removeAccount(_ email: String) {
        try? KeychainStore(accessGroup: nil).deleteRefreshToken(accountEmail: email)
        accounts.removeAll { $0 == email }
        store?.accountEmails = accounts

        let now = Date()
        if let file = CatalogStore(appGroupIdentifier: AppConfig.appGroupID), let catalog = file.read() {
            try? file.write(catalog.removing(accountEmail: email, generatedAt: now))
        }
        if let file = EventCache(appGroupIdentifier: AppConfig.appGroupID), var cache = file.read() {
            cache.sources.removeAll { $0.accountEmail == email }
            cache.events.removeAll { $0.accountEmail == email }
            try? file.write(cache)
        }
        WidgetReloader.reloadAll()
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
