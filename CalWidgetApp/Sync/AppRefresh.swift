import Foundation
import BackgroundTasks
import CalCore

/// Background + foreground refresh helpers for the app. Both delegate to `SyncCoordinator`
/// (a `today … +14d` canonical rebuild via the shared-Keychain refresh token) and reload
/// every widget.
enum AppRefresh {
    private static var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }

    /// Runs a canonical sync and reloads every widget. Used by the BGTask handler.
    static func runBackgroundRefresh() async {
        await SyncCoordinator.refreshCanonical(calendar: calendar)
        WidgetReloader.reloadAll()
        schedule()
    }

    /// Refreshes on foreground, but only if the cache is stale enough to be worth a network
    /// call (avoids syncing on every quick app switch).
    static func refreshOnForegroundIfStale(maxAge: TimeInterval = 15 * 60) async {
        if let last = AppGroupStore(suiteName: AppConfig.appGroupID)?.lastSyncedAt,
           Date().timeIntervalSince(last) < maxAge {
            return
        }
        await SyncCoordinator.refreshCanonical(calendar: calendar)
        WidgetReloader.reloadAll()
    }

    /// Schedules the next background refresh (~1h out; the OS decides actual timing).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.backgroundRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
