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
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
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

    var body: some View {
        NavigationStack {
            if auth.isSignedIn {
                CalendarPickerView()
            } else {
                SignInView()
            }
        }
    }
}
