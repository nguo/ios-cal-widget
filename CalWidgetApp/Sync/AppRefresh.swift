import Foundation
import BackgroundTasks
import CalCore

/// Background + foreground refresh helpers for the app. Both relist the accounts' calendars and
/// then run a canonical rebuild via the shared-Keychain refresh tokens, and reload every widget.
///
/// Both are subject to `refreshCanonical`'s cross-process claim, so neither can start behind a
/// widget intent's sync — these fire on a schedule the user doesn't see, so an unguarded one
/// could replace the cache underneath a pagination fetch the user had just triggered.
enum AppRefresh {
    private static var calendar: Calendar { .calWidget }

    /// Relists every account's calendars, syncs, and reloads every widget. Used by the BGTask
    /// handler. The catalog pass is what makes a calendar added in Google Calendar show up in the
    /// widget's picker without the user opening this app and waiting.
    static func runBackgroundRefresh() async {
        await SyncCoordinator.refreshCatalog(calendar: calendar)
        // A skipped sync changed nothing, so there's nothing for the widgets to re-read.
        if await WidgetDemand.refreshCanonical(calendar: calendar).ran {
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
        await SyncCoordinator.refreshCatalog(calendar: calendar)
        if await WidgetDemand.refreshCanonical(calendar: calendar).ran {
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
