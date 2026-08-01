import AppIntents
import Foundation
import CalCore

/// Manual refresh intent. Guards against concurrent/double-tap syncs via the shared sync flag,
/// reflects the in-flight state in the widget (dimmed button), then rebuilds the canonical range
/// via `SyncCoordinator` (which reads the refresh token from the shared Keychain — no
/// GoogleSignIn SDK in the extension).
struct RefreshNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Calendar"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        // `refreshCanonical` owns the double-tap / concurrent guard: it claims the shared flag and
        // returns `.skipped` if a sync is already running.
        let outcome = await SyncCoordinator.refreshCanonical(calendar: .calWidget) {
            // Runs once the flag is claimed, so the rebuilt entry reads it as in-flight. Only the
            // grid renders that state, so dimming is a grid-only reload.
            WidgetReloader.reload(kind: AppConfig.twoWeekWidgetKind)
        }
        // Reload only when this call actually held the flag — it dimmed the button and must undim
        // it. On `.skipped` the sync that does hold it reloads when it finishes.
        if outcome.ran {
            WidgetReloader.reloadAll() // the cache may have changed — every widget re-reads it
        }
        return .result()
    }
}
