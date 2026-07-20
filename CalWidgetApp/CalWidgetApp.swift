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
    /// True once this process has backgrounded at least once — i.e. later foregrounds are fast
    /// resumes, not a cold launch. Gates the deep-link forward delay (cold launch only). Resets to
    /// false on a fresh process, since @State lives as long as the app session.
    @State private var hasBackgrounded = false

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
            switch phase {
            case .active: openPendingDeepLink()
            case .background: hasBackgrounded = true // later foregrounds are fast resumes, not cold
            default: break
            }
        }
        .onOpenURL { url in
            // Widget `Link`s (two-week grid) open the host app and deliver their destination here
            // rather than launching an external app. OAuth callbacks arrive on a custom scheme (not
            // google.com) and go to GIDSignIn; Google Calendar links are forwarded via the same
            // stash-and-forward path as the agenda widget. Forwarding synchronously here is too
            // early (mid-activation) — Google Calendar drops the hand-off and just resumes its
            // previous view — so we defer to openPendingDeepLink, which runs once the app is active.
            if DeepLinkBuilder.isTrustedGoogleHost(url) {
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
        // Clear before validating, so a link we refuse to open can't wedge the queue.
        store.pendingDeepLink = nil
        // Re-check here rather than trusting the writer: this drains shared cross-process
        // storage, and the value is opened directly with `openURL`.
        guard DeepLinkBuilder.isTrustedGoogleHost(url) else { return }
        // Only a cold launch (fresh process, not yet backgrounded) is slow enough to foreground that
        // forwarding mid-transition races Google Calendar — it drops the deep link's date and lands
        // on today — so defer just that case. A resume from background is fast, so forward at once.
        // (The removed debug alert masked the race by adding a human-scale delay to every tap.)
        let isColdLaunch = !hasBackgrounded
        Task { @MainActor in
            if isColdLaunch { try? await Task.sleep(for: .milliseconds(500)) }
            openURL(url)
        }
    }
}
