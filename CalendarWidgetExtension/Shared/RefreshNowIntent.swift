import AppIntents
import Foundation
import CalCore

/// Manual refresh intent. Guards against concurrent/double-tap syncs via the shared sync flag,
/// reflects the in-flight state in the widget (dimmed button), then refetches the cached range
/// via `SyncCoordinator` (which reads the refresh token from the shared Keychain — no
/// GoogleSignIn SDK in the extension).
struct RefreshNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Calendar"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        guard let store = AppGroupStore(suiteName: AppConfig.appGroupID) else { return .result() }
        guard !store.isSyncing else { return .result() } // double-tap / concurrent guard

        store.beginSync()
        // Only the grid renders the in-flight state, so dimming is a grid-only reload.
        WidgetReloader.reload(kind: AppConfig.twoWeekWidgetKind)
        defer {
            store.endSync()
            WidgetReloader.reloadAll() // the cache may have changed — every widget re-reads it
        }

        var cal = Calendar.current
        cal.firstWeekday = 1
        await SyncCoordinator.refetchAll(calendar: cal)
        return .result()
    }
}
