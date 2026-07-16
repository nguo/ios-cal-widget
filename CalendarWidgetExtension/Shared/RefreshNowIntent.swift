import AppIntents
import WidgetKit
import CalCore

/// Manual refresh intent. Guards against concurrent/double-tap syncs via the shared
/// `isSyncing` flag, reflects the in-flight state in the widget (dimmed button), then rebuilds
/// the canonical −2/+6-week window via `SyncCoordinator` (which reads the refresh token from
/// the shared Keychain — no GoogleSignIn SDK in the extension).
struct RefreshNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Calendar"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        guard let store = AppGroupStore(suiteName: AppConfig.appGroupID) else { return .result() }
        guard !store.isSyncing else { return .result() } // double-tap / concurrent guard

        store.isSyncing = true
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.twoWeekWidgetKind) // show dimmed state
        defer {
            store.isSyncing = false
            WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.twoWeekWidgetKind)
        }

        var cal = Calendar.current
        cal.firstWeekday = 1
        await SyncCoordinator.refetchAll(calendar: cal)
        return .result()
    }
}
