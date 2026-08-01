import Foundation

/// What a sync attempt did. `skipped` is distinct from `failed` on purpose: a skipped sync never
/// claimed the flag and never touched the in-flight state, so callers that reload widgets to
/// clear a spinner must not treat it as a finished sync — whoever holds the flag will reload.
public enum SyncOutcome: Equatable, Sendable {
    /// Another sync was already in flight; this one did nothing.
    case skipped
    /// Ran and replaced the cache.
    case succeeded
    /// Ran (or couldn't start for lack of credentials) and left the cache untouched.
    case failed

    /// Whether this attempt actually held the flag, i.e. the in-flight state changed.
    public var ran: Bool { self != .skipped }
}

/// Credential-driven sync used by the widget's refresh intent, the pagination intent, and the
/// app's background/foreground refresh. Reads the refresh token from the shared Keychain and
/// the selected calendars from the existing cache — no GoogleSignIn SDK needed, so it runs in
/// the widget extension too. All writes are atomic (`EventCache.write`).
public enum SyncCoordinator {
    /// The rolling canonical window: today .. `agendaHorizonDays` after. Kept intentionally small —
    /// paging backfills anything beyond it on demand (see `fetchRangeIfNeeded`).
    ///
    /// The end is *derived* from the agenda's horizon rather than hardcoded to match it. The agenda
    /// asks for exactly `today … today + agendaHorizonDays` and nothing tells it when the cache
    /// falls short — it just renders fewer days. Worse, `CoverageRefresh` would then see `covers()`
    /// false on every timeline build and fetch on each one, since no sync could ever satisfy a
    /// horizon the canonical range doesn't reach. Deriving it means raising the horizon widens the
    /// fetch automatically.
    public static func canonicalRange(calendar: Calendar, now: Date) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let start = today
        let end = calendar.date(byAdding: .day, value: AppConfig.agendaHorizonDays, to: today)!
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
    /// Leaves any existing cache untouched unless the fetch fully succeeds.
    ///
    /// Replacing rather than merging is what keeps the cache bounded: every sync entry point
    /// lands here, so the file is always exactly one canonical range and nothing accumulates.
    /// Pagination is the one writer that merges (`fetchWindowIfNeeded`), and the next sync
    /// reclaims whatever it added.
    ///
    /// Claims the shared cross-process sync flag itself and returns `.skipped` when another sync
    /// already holds it. The guard lives here rather than at each call site because this replaces
    /// the whole cache: two overlapping syncs mean the loser's write is silently discarded, and
    /// when the loser is a pagination fetch the widget lands on the page it just navigated to with
    /// no events. Guarding at the call sites left the app's foreground and background refreshes
    /// unguarded in both directions.
    ///
    /// `onClaim` runs after the flag is claimed and before the fetch — for callers that need to
    /// show the in-flight state, which is only readable once the flag is set.
    @discardableResult
    public static func refreshCanonical(
        weekCount: Int = AppConfig.gridWeekCount,
        calendar: Calendar,
        now: Date = Date(),
        onClaim: () -> Void = {}
    ) async -> SyncOutcome {
        guard let ctx = context() else { return .failed }
        // Claim after `context()`: a signed-out process can't sync, so it shouldn't spend the flag.
        guard ctx.store.claimSync(now: now) else { return .skipped }
        defer { ctx.store.endSync() }
        onClaim()

        let range = canonicalRange(coveringOffset: ctx.store.twoWeekPageOffset, weekCount: weekCount, calendar: calendar, now: now)
        do {
            let cache = try await fetch(ctx: ctx, calendar: calendar, start: range.start, end: range.end, now: now)
            try EventCache(appGroupIdentifier: AppConfig.appGroupID)?.write(cache)
            ctx.store.lastSyncedAt = now
            return .succeeded
        } catch {
            return .failed
        }
    }

    /// If the window for `pageOffset` isn't fully covered by the cache, fetches just that range
    /// and appends it (widening the cached window). Used to auto-load unfetched ranges when the
    /// user paginates. No-ops (returns true) when the range is already cached.
    ///
    /// Unlike `refreshCanonical`, the **caller** owns the sync claim here: `ShiftWindowIntent`
    /// must hold it from before it publishes the new page offset until after this returns, so a
    /// second tap can't page ahead of the fetch. Claiming internally would leave that gap open.
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
