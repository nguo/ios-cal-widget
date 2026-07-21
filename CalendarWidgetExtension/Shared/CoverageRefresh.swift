import Foundation
import CalCore

/// Closes the gap between the widgets' midnight reload and the app's sync schedule.
///
/// Both timeline providers reload at midnight, but that is a *render-only* reload: the provider
/// re-reads the cache so "today" advances, and nothing refetches. The cached window still ends at
/// whatever `today + 14d` meant at the last sync, so it falls one day short of the horizon per day
/// that passes — invisible for the agenda (the far day just renders empty), but at a week rollover
/// the grid's window jumps to the new Sunday, `covers` goes false, and the widget sits on the "tap
/// to refresh" banner until a `BGAppRefreshTask` lands. That task is best-effort, iOS throttles it
/// for apps opened rarely, and it is only ever scheduled from the *app* — so a widget-only user may
/// wait a long time. Since `SyncCoordinator` runs in the extension, the provider can just fix it.
enum CoverageRefresh {
    /// Syncs when `start ..< end` isn't fully cached, and returns the fresh cache if it did.
    /// Returns nil — meaning "carry on with what's on disk" — when the range is already covered,
    /// another sync is in flight, or the sync failed.
    @discardableResult
    static func syncIfUncovered(
        start: Date,
        end: Date,
        calendar: Calendar = .calWidget,
        now: Date = Date()
    ) async -> EventCacheData? {
        guard
            let store = AppGroupStore(suiteName: AppConfig.appGroupID),
            let file = EventCache(appGroupIdentifier: AppConfig.appGroupID)
        else { return nil }

        // Nothing on disk yet is the un-synced/signed-out case, not a stale one. `refreshCanonical`
        // would bail anyway (it reads the selected calendars *from* the cache), so don't spend the
        // flag or the launch on it.
        guard let existing = file.read() else { return nil }
        guard !existing.covers(start: start, end: end) else { return nil }

        // All three widgets reload on the same midnight tick and would each fire their own fetch of
        // the same range. First one to claim the flag does the work; the others render from disk and
        // pick up the result via the reload below.
        guard !store.isSyncing else { return nil }
        store.beginSync()
        defer { store.endSync() }

        guard await SyncCoordinator.refreshCanonical(calendar: calendar, now: now) else { return nil }
        // Re-check coverage rather than assuming: if a sync somehow still can't cover this range,
        // returning nil here stops the reload, and with it any chance of a reload/sync loop.
        guard let fresh = file.read(), fresh.covers(start: start, end: end) else { return nil }

        WidgetReloader.reloadAll() // the cache changed — siblings built from the stale copy
        return fresh
    }
}
