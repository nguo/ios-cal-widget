import SwiftUI
import GoogleSignIn
import CalCore

@main
struct CalWidgetApp: App {
    @StateObject private var auth = GoogleAuthService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .task { await auth.restore() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await AppRefresh.refreshOnForegroundIfStale() }
            case .background:
                AppRefresh.schedule()
            default:
                break
            }
        }
        // Registers the BGTask handler (paired with BGTaskSchedulerPermittedIdentifiers).
        .backgroundTask(.appRefresh(AppConfig.backgroundRefreshTaskID)) {
            await AppRefresh.runBackgroundRefresh()
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: GoogleAuthService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            if auth.isSignedIn {
                CalendarPickerView()
            } else {
                SignInView()
            }
        }
        // A tapped agenda-widget row opens the app (via OpenDeepLinkIntent) with a Google Calendar
        // URL stashed in the App Group; forward to it and clear. Handled on first appear (cold
        // launch, where no scenePhase change fires) and on every activation (warm launch).
        .task { openPendingDeepLink() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { openPendingDeepLink() }
        }
        .onOpenURL { url in
            // Widget `Link`s (two-week grid) open the host app and deliver their destination here
            // rather than launching an external app. OAuth callbacks arrive on a custom scheme (not
            // google.com) and go to GIDSignIn; Google Calendar links are forwarded via the same
            // stash-and-forward path as the agenda widget. Forwarding synchronously here is too
            // early (mid-activation) — Google Calendar drops the hand-off and just resumes its
            // previous view — so we defer to openPendingDeepLink, which runs once the app is active.
            if url.host?.hasSuffix("google.com") == true {
                AppGroupStore(suiteName: AppConfig.appGroupID)?.pendingDeepLink = url.absoluteString
                Task { @MainActor in openPendingDeepLink() }
            } else {
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }

    /// Forwards a stashed Google Calendar deep link (from either widget) to Google Calendar, once.
    /// Runs on first appear, on activation, and just after a widget `Link` delivers a URL; the
    /// clear dedupes across those triggers.
    private func openPendingDeepLink() {
        guard let store = AppGroupStore(suiteName: AppConfig.appGroupID),
              let link = store.pendingDeepLink,
              let url = URL(string: link) else { return }
        store.pendingDeepLink = nil
        openURL(url)
    }
}
