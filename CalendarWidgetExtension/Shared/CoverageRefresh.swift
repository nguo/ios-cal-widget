import Foundation
import CalCore

/// Closes the gap between the widgets' midnight reload and the app's sync schedule, and the gap
/// between a widget's calendar selection changing and the next sync noticing.
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
    /// Syncs when the cache doesn't already hold `refs` over `start ..< end`, and returns the
    /// fresh cache if it did. Returns nil — meaning "carry on with what's on disk" — when
    /// everything asked for is covered, another sync is in flight, or the sync failed.
    ///
    /// Coverage is two-dimensional now that events are fetched on demand. The date range is the
    /// original reason this exists (midnight walks the horizon forward). `refs` is the second: the
    /// moment the user adds a calendar in Edit Widget, this provider runs with a selection the
    /// cache has never fetched, over a range it *does* cover. Without the ref check that widget
    /// renders the new calendar empty until something else happens to sync.
    @discardableResult
    static func syncIfUncovered(
        start: Date,
        end: Date,
        refs: Set<CalendarRef>,
        calendar: Calendar = .calWidget,
        now: Date = Date()
    ) async -> EventCacheData? {
        guard let file = EventCache(appGroupIdentifier: AppConfig.appGroupID) else { return nil }

        // An unconfigured widget asks for nothing, so there's nothing to be short of. Also keeps
        // the gallery and a signed-out install off the network.
        guard !refs.isEmpty else { return nil }

        // No cache at all is the first-run case and *is* worth syncing now: the demanded refs
        // resolve through the catalog, so a sync can seed from nothing. (It couldn't when the
        // calendars to fetch were read out of the cache itself.)
        let existing = file.read()
        if let existing, existing.covers(start: start, end: end), existing.covers(refs: refs) { return nil }

        // All three widgets reload on the same midnight tick and would each fire their own fetch of
        // the same range. `refreshCanonical` claims the shared flag, so the first one does the work
        // and the rest return `.skipped`, render from disk, and pick up the result via its reload.
        guard await WidgetDemand.refreshCanonical(calendar: calendar, now: now) == .succeeded else { return nil }
        // Re-check coverage rather than assuming: if a sync somehow still can't cover this, returning
        // nil here stops the reload, and with it any chance of a reload/sync loop.
        guard let fresh = file.read(), fresh.covers(start: start, end: end), fresh.covers(refs: refs) else { return nil }

        // The cache changed and the siblings built from the stale copy. This also reloads the
        // caller, which is still mid-build — one redundant rebuild, which then finds `covers()`
        // true and stops, so it can't loop. Targeting only the siblings would need an enumerable
        // list of widget kinds, and a list that falls behind a newly added widget leaves that
        // widget stranded on stale data — a worse failure than a rebuild that happens at most
        // once per rollover. The caller uses the returned cache, so its first build isn't wasted.
        WidgetReloader.reloadAll()
        return fresh
    }
}
