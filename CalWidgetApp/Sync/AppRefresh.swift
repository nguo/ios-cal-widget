import Foundation
import BackgroundTasks
import CalCore

/// Background + foreground refresh helpers for the app. Both delegate to `SyncCoordinator`
/// (a canonical rebuild via the shared-Keychain refresh token) and reload every widget.
///
/// Both are subject to `refreshCanonical`'s cross-process claim, so neither can start behind a
/// widget intent's sync — these fire on a schedule the user doesn't see, so an unguarded one
/// could replace the cache underneath a pagination fetch the user had just triggered.
enum AppRefresh {
    private static var calendar: Calendar { .calWidget }

    /// Runs a canonical sync and reloads every widget. Used by the BGTask handler.
    static func runBackgroundRefresh() async {
        // A skipped sync changed nothing, so there's nothing for the widgets to re-read.
        if await SyncCoordinator.refreshCanonical(calendar: calendar).ran {
            WidgetReloader.reloadAll()
        }
        schedule()
    }

    /// Refreshes on foreground, but only if the cache is stale enough to be worth a network
    /// call (avoids syncing on every quick app switch).
    static func refreshOnForegroundIfStale(maxAge: TimeInterval = 15 * 60) async {
        if let last = AppGroupStore(suiteName: AppConfig.appGroupID)?.lastSyncedAt,
           Date().timeIntervalSince(last) < maxAge {
            return
        }
        if await SyncCoordinator.refreshCanonical(calendar: calendar).ran {
            WidgetReloader.reloadAll()
        }
    }

    /// Schedules the next background refresh (~1h out; the OS decides actual timing).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.backgroundRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
