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

/// Credential-driven sync used by the widget's refresh intent, the pagination intent, the app's
/// background/foreground refresh, and the app's own "Sync now". Reads each account's refresh
/// token from the shared Keychain — no GoogleSignIn SDK needed, so it runs in the widget
/// extension too. All writes are atomic (`EventCache.write` / `CatalogStore.write`).
///
/// Two passes, deliberately separate:
///
/// - `refreshCatalog` lists *what calendars exist* across every signed-in account. One request
///   per account.
/// - `refreshCanonical` fetches *events*, for the calendars some placed widget actually selected
///   (`AppGroupStore.demandedCalendarRefs`) — never for the whole catalog.
///
/// Splitting them is what makes multi-account viable. Fetching every calendar of every account
/// was fine at one account and is not at three: 45 event requests won't finish inside an App
/// Intent's budget and draw Google's rate limiter besides.
///
/// **Never call `refreshCanonical` directly from app or extension code — go through
/// `WidgetDemand.refreshCanonical`,** which refreshes the demand mirror first. The mirror is the
/// only thing this can read, and a stale one means a calendar the user just selected is never
/// fetched.
public enum SyncCoordinator {
    /// The rolling canonical window: today .. `agendaHorizonDays` after. Kept intentionally small —
    /// paging backfills anything beyond it on demand (see `fetchWindowIfNeeded`).
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
    /// week's Sunday — before `today` on any non-Sunday — and so falls outside the canonical
    /// range, which starts at today. Paged offsets fall outside too. Without this widening a
    /// canonical sync leaves that window uncovered, so the widget shows the "tap to refresh"
    /// banner even though fresh events are visible.
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

    /// Rebuilds the canonical window fresh and replaces the cache with exactly it
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
            let result = try await fetch(ctx: ctx, calendar: calendar, start: range.start, end: range.end, now: now)
            // An account that answered for nothing at all keeps its previous events rather than
            // being written out of the cache — see `EventCacheData.carryingForward`.
            let cache = ctx.existing.map {
                result.cache.carryingForward(
                    accounts: unreachableAccounts(demanded: ctx.demanded, failedRefs: result.failedRefs),
                    from: $0
                )
            } ?? result.cache
            try EventCache(appGroupIdentifier: AppConfig.appGroupID)?.write(cache)
            ctx.store.lastSyncedAt = now
            return .succeeded
        } catch {
            return .failed
        }
    }

    /// Lists every signed-in account's calendars and replaces the catalog. Cheap — one request
    /// per account — and the only thing that discovers a calendar exists, so the widget's picker
    /// and every ref lookup depend on it.
    ///
    /// An account whose listing fails keeps its previous entries instead of being dropped:
    /// dropping them empties that half of the picker and makes live widget selections
    /// unresolvable, which reads to the user as the widget forgetting its calendars over a
    /// transient network blip.
    ///
    /// Not part of the render path. It runs from the app's foreground/background refresh and
    /// after an account is added or removed.
    @discardableResult
    public static func refreshCatalog(calendar: Calendar, now: Date = Date()) async -> Bool {
        guard
            let store = AppGroupStore(suiteName: AppConfig.appGroupID),
            let file = CatalogStore(appGroupIdentifier: AppConfig.appGroupID)
        else { return false }
        let accounts = store.accountEmails
        guard !accounts.isEmpty else { return false }

        let tokens = await accessTokens(for: Set(accounts))
        let sync = CalendarSyncService(api: GoogleCalendarAPIClient(), calendar: calendar)
        var catalog = file.read() ?? CalendarCatalog(generatedAt: now, sources: [])
        var listedAny = false

        for email in accounts {
            guard let fresh = try? await sync.listCalendars(accountEmail: email, tokenProvider: { account in
                guard let token = tokens[account] else { throw SyncError.missingCredentials(account) }
                return token
            }) else { continue }
            catalog = catalog.replacing(accountEmail: email, with: fresh, generatedAt: now)
            listedAny = true
        }

        // Accounts removed while this ran, or removed by another process, shouldn't linger.
        for stale in Set(catalog.accountEmails).subtracting(accounts) {
            catalog = catalog.removing(accountEmail: stale, generatedAt: now)
        }

        guard listedAny else { return false }
        try? file.write(catalog)
        return true
    }

    /// The accounts whose *every* demanded calendar failed. One flaky calendar is a partial
    /// failure and stays partial; a whole account going quiet is the multi-account form of a
    /// total failure, and is what `carryingForward` protects.
    public static func unreachableAccounts(
        demanded: [CalendarSource],
        failedRefs: Set<CalendarRef>
    ) -> Set<String> {
        var byAccount: [String: (total: Int, failed: Int)] = [:]
        for source in demanded {
            var tally = byAccount[source.accountEmail] ?? (0, 0)
            tally.total += 1
            if failedRefs.contains(source.ref) { tally.failed += 1 }
            byAccount[source.accountEmail] = tally
        }
        return Set(byAccount.filter { $0.value.total == $0.value.failed }.keys)
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
        guard let ctx = context(), let existing = ctx.existing else { return false }
        let window = DateWindow(referenceDate: now, pageOffset: pageOffset, weekCount: weekCount, calendar: calendar)
        if existing.covers(start: window.startDate, end: window.endExclusive) { return true }

        do {
            let fetched = try await fetch(ctx: ctx, calendar: calendar, start: window.startDate, end: window.endExclusive, now: now)
            // No carry-forward needed here: `appending` keeps what's already cached, so an account
            // that failed simply contributes nothing new.
            let merged = existing.appending(
                events: fetched.cache.events,
                sources: fetched.cache.sources,
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
        /// Catalog ∩ demand: exactly the calendars to fetch events for, possibly across accounts.
        let demanded: [CalendarSource]
        /// nil before the first successful sync. Not required to start one — the catalog and the
        /// demand mirror say what to fetch, which is what lets a first run seed the cache.
        let existing: EventCacheData?
    }

    /// Gathers what any event sync needs: the demanded calendars, resolved through the catalog.
    ///
    /// Deliberately does **not** derive the calendars from the existing cache, which is what the
    /// single-account version did. That made the cache its own input, so nothing could seed it and
    /// the app had to keep a second, duplicated fetch path just for first run.
    private static func context() -> Context? {
        guard
            let store = AppGroupStore(suiteName: AppConfig.appGroupID),
            !store.accountEmails.isEmpty,
            let catalog = CatalogStore(appGroupIdentifier: AppConfig.appGroupID)?.read()
        else { return nil }

        // Nothing selected anywhere means there is genuinely nothing to fetch — a fresh install
        // whose widgets are all unconfigured. Treated as "couldn't start", same as signed out.
        let demanded = catalog.resolve(store.demandedCalendarRefs)
        guard !demanded.isEmpty else { return nil }

        return Context(
            store: store,
            demanded: demanded,
            existing: EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read()
        )
    }

    /// One access token per account, minted up front. Sequential because the count is accounts,
    /// not calendars — a handful at most. An account whose token can't be minted is simply absent
    /// from the result; its calendars then fail individually and land in `failedRefs`, which is
    /// what lets a revoked account be carried forward instead of blanking.
    private static func accessTokens(for accounts: Set<String>) async -> [String: String] {
        let keychain = KeychainStore(accessGroup: nil)
        let service = TokenRefreshService(clientID: AppConfig.googleClientID)
        var tokens: [String: String] = [:]
        for email in accounts.sorted() {
            guard
                let refreshToken = try? keychain.refreshToken(accountEmail: email),
                let access = try? await service.accessToken(refreshToken: refreshToken)
            else { continue }
            tokens[email] = access.token
        }
        return tokens
    }

    private static func fetch(
        ctx: Context, calendar: Calendar, start: Date, end: Date, now: Date
    ) async throws -> CalendarSyncService.SyncResult {
        let tokens = await accessTokens(for: Set(ctx.demanded.map(\.accountEmail)))
        guard !tokens.isEmpty else { throw SyncError.allCalendarsFailed }

        let sync = CalendarSyncService(api: GoogleCalendarAPIClient(), calendar: calendar)
        guard let result = await sync.buildCache(
            sources: ctx.demanded,
            rangeStart: start,
            rangeEnd: end,
            now: now,
            tokenProvider: { account in
                guard let token = tokens[account] else { throw SyncError.missingCredentials(account) }
                return token
            }
        ) else {
            // Every calendar failed. Throwing here means the callers' `catch` paths skip the
            // write entirely, leaving the last good cache in place.
            throw SyncError.allCalendarsFailed
        }
        return result
    }
}
