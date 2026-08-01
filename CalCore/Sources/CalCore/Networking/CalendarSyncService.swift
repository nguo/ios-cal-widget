import Foundation

/// Orchestrates a sync: for each selected calendar, fetch events in a date range, map them
/// to flat `CalendarEvent`s (color denormalized from the source), merge across all calendars,
/// and produce an `EventCacheData`. Foundation-only and transport-injected, so it's testable
/// off-device. The caller writes the result via `EventCache.write` (atomic).
public struct CalendarSyncService {
    private let api: GoogleCalendarAPIClient
    private let calendar: Calendar
    private let maxConcurrentFetches: Int

    /// Supplies a valid access token for a given account email (e.g. via `TokenRefreshService`).
    public typealias AccessTokenProvider = @Sendable (_ accountEmail: String) async throws -> String

    /// - Parameter maxConcurrentFetches: how many calendars to fetch at once. Unbounded
    ///   parallelism meant a user with thirty calendars fired thirty simultaneous requests and
    ///   drew Google's `rateLimitExceeded` — which then looked like calendars that simply had
    ///   no events.
    public init(api: GoogleCalendarAPIClient, calendar: Calendar, maxConcurrentFetches: Int = 5) {
        self.api = api
        self.calendar = calendar
        self.maxConcurrentFetches = max(1, maxConcurrentFetches)
    }

    /// What a sync produced, plus which calendars didn't answer. The failure list isn't
    /// diagnostic decoration: with several accounts signed in, the caller needs it to tell "one
    /// calendar was flaky" from "this whole account is revoked", and only the latter warrants
    /// carrying the previous events forward.
    public struct SyncResult: Sendable {
        public let cache: EventCacheData
        public let failedRefs: Set<CalendarRef>

        public init(cache: EventCacheData, failedRefs: Set<CalendarRef>) {
            self.cache = cache
            self.failedRefs = failedRefs
        }
    }

    /// Builds the canonical cache for the given range across every source passed in — which is
    /// the *demanded* set, i.e. the calendars some placed widget selected, possibly spanning
    /// accounts. Fetches calendars concurrently.
    ///
    /// A *partial* failure is tolerated: that calendar's events are omitted and the rest still
    /// populate, since partial data beats no data. A *total* failure is not — returns nil when
    /// every calendar failed, so the caller skips the write and the previous cache survives.
    /// Writing the empty result instead produced a cache that looked freshly synced but had no
    /// events, silently blanking the widget after a transient network drop.
    public func buildCache(
        sources: [CalendarSource],
        rangeStart: Date,
        rangeEnd: Date,
        now: Date,
        tokenProvider: @escaping AccessTokenProvider
    ) async -> SyncResult? {
        typealias Fetched = (ref: CalendarRef, events: [CalendarEvent]?)
        let perCalendar: [Fetched] = await withTaskGroup(of: Fetched.self) { group in
            var next = 0
            // Keep at most `maxConcurrentFetches` requests in flight: start a batch, then add
            // one more each time a result lands.
            func addTask() {
                let source = sources[next]
                next += 1
                group.addTask {
                    (source.ref, await self.fetchEvents(for: source, rangeStart: rangeStart, rangeEnd: rangeEnd, tokenProvider: tokenProvider))
                }
            }
            while next < min(maxConcurrentFetches, sources.count) { addTask() }

            var collected: [Fetched] = []
            while let result = await group.next() {
                collected.append(result)
                if next < sources.count { addTask() }
            }
            return collected
        }

        let succeeded = perCalendar.compactMap(\.events)
        // Nothing came back at all — treat as a failed sync, not an empty calendar.
        guard !sources.isEmpty, !succeeded.isEmpty else { return nil }

        let merged = succeeded.flatMap { $0 }.sorted { $0.startDate < $1.startDate }
        return SyncResult(
            cache: EventCacheData(
                generatedAt: now,
                windowStart: rangeStart,
                windowEnd: rangeEnd,
                sources: sources,
                events: merged
            ),
            failedRefs: Set(perCalendar.filter { $0.events == nil }.map(\.ref))
        )
    }

    /// Every calendar the account can see, mapped to `CalendarSource`. One request per account
    /// per sync, which is what makes demand-driven event fetching affordable: adding an account
    /// costs this call, not an event fetch per calendar it owns.
    public func listCalendars(
        accountEmail: String,
        tokenProvider: @escaping AccessTokenProvider
    ) async throws -> [CalendarSource] {
        let token = try await tokenProvider(accountEmail)
        return try await api.calendarList(accessToken: token).map { entry in
            CalendarSource(
                id: entry.id,
                accountEmail: accountEmail,
                summary: entry.summary ?? entry.id,
                colorHex: entry.backgroundColor ?? "#4285F4",
                isFreeBusyOnly: entry.isFreeBusyOnly
            )
        }
    }

    /// One calendar's events, or nil if the fetch failed (distinct from a genuinely empty
    /// calendar, which returns an empty array — `buildCache` needs to tell those apart).
    private func fetchEvents(
        for source: CalendarSource,
        rangeStart: Date,
        rangeEnd: Date,
        tokenProvider: @escaping AccessTokenProvider
    ) async -> [CalendarEvent]? {
        // Retry only rate-limiting. Backoff is deliberately short: this also runs inside App
        // Intents, which are killed if they overrun a tight time budget.
        let backoff: [Duration] = [.milliseconds(300), .milliseconds(900)]
        for attempt in 0 ... backoff.count {
            do {
                let token = try await tokenProvider(source.accountEmail)
                let page = try await api.events(
                    calendarId: source.id,
                    accessToken: token,
                    timeMin: rangeStart,
                    timeMax: rangeEnd
                )
                return page.events.compactMap { gcal in
                    try? CalendarEvent.from(gcal, ref: source.ref, colorHex: source.colorHex,
                                            calendar: calendar, isFreeBusyOnly: source.isFreeBusyOnly)
                }
            } catch {
                guard attempt < backoff.count, Self.isRateLimited(error) else { return nil }
                try? await Task.sleep(for: backoff[attempt])
            }
        }
        return nil
    }

    /// Google signals throttling as 429, or as a 403 whose body names a rate-limit reason.
    static func isRateLimited(_ error: Error) -> Bool {
        guard case let HTTPError.status(code, body) = error else { return false }
        if code == 429 { return true }
        guard code == 403 else { return false }
        return body.contains("rateLimitExceeded")
            || body.contains("userRateLimitExceeded")
            || body.contains("quotaExceeded")
    }
}

/// Failures that abort a whole sync (as opposed to one calendar).
public enum SyncError: Error, Equatable {
    /// Every calendar's fetch failed — almost always no network or a revoked token.
    case allCalendarsFailed
    /// No usable access token for this account. Thrown per calendar, so the other accounts'
    /// calendars still fetch and this one's land in `SyncResult.failedRefs`.
    case missingCredentials(String)
}
