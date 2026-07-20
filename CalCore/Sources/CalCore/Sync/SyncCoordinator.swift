import Foundation

/// Credential-driven sync used by the widget's refresh intent, the pagination intent, and the
/// app's background/foreground refresh. Reads the refresh token from the shared Keychain and
/// the selected calendars from the existing cache — no GoogleSignIn SDK needed, so it runs in
/// the widget extension too. All writes are atomic (`EventCache.write`).
public enum SyncCoordinator {
    /// The rolling canonical window: today .. 2 weeks after. Kept intentionally small — paging
    /// backfills anything beyond it on demand (see `fetchRangeIfNeeded`).
    public static func canonicalRange(calendar: Calendar, now: Date) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let start = today
        let end = calendar.date(byAdding: .day, value: 14, to: today)!
        return (start, end)
    }

    /// The canonical range, widened so it also fully covers the widget window at `pageOffset`.
    /// The grid widget's window is week-aligned, so even at offset 0 it starts on the current
    /// week's Sunday — before `today` on any non-Sunday — and thus falls outside the canonical
    /// `today … +2wk` range. Paged offsets fall outside too. Without this widening a canonical
    /// sync leaves that window uncovered, so the widget shows the "tap to refresh" banner even
    /// though fresh events are visible.
    public static func canonicalRange(
        coveringOffset pageOffset: Int,
        weekCount: Int,
        calendar: Calendar,
        now: Date
    ) -> (start: Date, end: Date) {
        var (start, end) = canonicalRange(calendar: calendar, now: now)
        let window = DateWindow(referenceDate: now, pageOffset: pageOffset, weekCount: weekCount, calendar: calendar)
        start = min(start, window.startDate)
        end = max(end, window.endExclusive)
        return (start, end)
    }

    /// Rebuilds the canonical today/+2wk window fresh and replaces the cache with exactly it
    /// (discarding any ranges pagination had appended beyond), widened to still cover the
    /// widget's currently-paged window so a paged widget isn't stranded on the stale banner.
    /// Returns false if not signed in / no selected calendars — leaving any existing cache
    /// untouched.
    @discardableResult
    public static func refreshCanonical(weekCount: Int = 2, calendar: Calendar, now: Date = Date()) async -> Bool {
        guard let ctx = context() else { return false }
        let range = canonicalRange(coveringOffset: ctx.store.twoWeekPageOffset, weekCount: weekCount, calendar: calendar, now: now)
        do {
            let cache = try await fetch(ctx: ctx, calendar: calendar, start: range.start, end: range.end, now: now)
            try EventCache(appGroupIdentifier: AppConfig.appGroupID)?.write(cache)
            ctx.store.lastSyncedAt = now
            return true
        } catch {
            return false
        }
    }
    
    /// Refetch the whole currently-fetched date range, widened to at least the canonical window
    /// covering the widget's current offset. The widening is what lets the "tap refresh" button
    /// clear the stale banner: without it a refetch reuses `existing`'s window verbatim, so a cache
    /// whose window had drifted narrower than the (week-aligned) widget window could never re-cover
    /// it — refresh would refetch the same too-narrow range and the banner would persist.
    @discardableResult
    public static func refetchAll(
        weekCount: Int = 2,
        calendar: Calendar,
        now: Date = Date()
    ) async -> Bool {
        guard let ctx = context() else { return false }

        let covering = canonicalRange(coveringOffset: ctx.store.twoWeekPageOffset, weekCount: weekCount, calendar: calendar, now: now)
        let start = min(ctx.existing.windowStart, covering.start)
        let end = max(ctx.existing.windowEnd, covering.end)
        do {
            let fetched = try await fetch(ctx: ctx, calendar: calendar, start: start, end: end, now: now)
            try EventCache(appGroupIdentifier: AppConfig.appGroupID)?.write(fetched)
            ctx.store.lastSyncedAt = now
            return true
        } catch {
            return false
        }
    }

    /// If the window for `pageOffset` isn't fully covered by the cache, fetches just that range
    /// and appends it (widening the cached window). Used to auto-load unfetched ranges when the
    /// user paginates. No-ops (returns true) when the range is already cached.
    @discardableResult
    public static func fetchWindowIfNeeded(
        pageOffset: Int,
        weekCount: Int,
        calendar: Calendar,
        now: Date = Date()
    ) async -> Bool {
        guard let ctx = context() else { return false }
        let window = DateWindow(referenceDate: now, pageOffset: pageOffset, weekCount: weekCount, calendar: calendar)
        if ctx.existing.covers(start: window.startDate, end: window.endExclusive) { return true }

        do {
            let fetched = try await fetch(ctx: ctx, calendar: calendar, start: window.startDate, end: window.endExclusive, now: now)
            let merged = ctx.existing.appending(
                events: fetched.events,
                sources: fetched.sources,
                rangeStart: window.startDate,
                rangeEnd: window.endExclusive,
                generatedAt: now
            )
            try EventCache(appGroupIdentifier: AppConfig.appGroupID)?.write(merged)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Internals

    private struct Context {
        let store: AppGroupStore
        let refreshToken: String
        let existing: EventCacheData
    }

    /// Gathers the credentials + selected calendars needed for any sync.
    private static func context() -> Context? {
        guard
            let store = AppGroupStore(suiteName: AppConfig.appGroupID),
            let email = store.accountEmail,
            let refreshToken = try? KeychainStore(accessGroup: nil).refreshToken(accountEmail: email),
            let existing = EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read(),
            !existing.sources.isEmpty
        else { return nil }
        return Context(store: store, refreshToken: refreshToken, existing: existing)
    }

    private static func fetch(ctx: Context, calendar: Calendar, start: Date, end: Date, now: Date) async throws -> EventCacheData {
        let access = try await TokenRefreshService(clientID: AppConfig.googleClientID)
            .accessToken(refreshToken: ctx.refreshToken)
        let sync = CalendarSyncService(api: GoogleCalendarAPIClient(), calendar: calendar)
        guard let cache = await sync.buildCache(
            sources: ctx.existing.sources,
            rangeStart: start,
            rangeEnd: end,
            now: now,
            tokenProvider: { _ in access.token }
        ) else {
            // Every calendar failed. Throwing here means the callers' `catch` paths skip the
            // write entirely, leaving the last good cache in place.
            throw SyncError.allCalendarsFailed
        }
        return cache
    }
}
