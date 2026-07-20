import Foundation

/// Orchestrates a sync: for each selected calendar, fetch events in a date range, map them
/// to flat `CalendarEvent`s (color denormalized from the source), merge across all calendars,
/// and produce an `EventCacheData`. Foundation-only and transport-injected, so it's testable
/// off-device. The caller writes the result via `EventCache.write` (atomic).
public struct CalendarSyncService {
    private let api: GoogleCalendarAPIClient
    private let calendar: Calendar

    /// Supplies a valid access token for a given account email (e.g. via `TokenRefreshService`).
    public typealias AccessTokenProvider = @Sendable (_ accountEmail: String) async throws -> String

    public init(api: GoogleCalendarAPIClient, calendar: Calendar) {
        self.api = api
        self.calendar = calendar
    }

    /// Builds the canonical cache for the given range across *every* source passed in — the
    /// cache is a superset of all available calendars, and each widget instance filters it to
    /// its own selection at render. Fetches calendars concurrently.
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
    ) async -> EventCacheData? {
        let perCalendar: [[CalendarEvent]?] = await withTaskGroup(of: [CalendarEvent]?.self) { group in
            for source in sources {
                group.addTask {
                    await self.fetchEvents(for: source, rangeStart: rangeStart, rangeEnd: rangeEnd, tokenProvider: tokenProvider)
                }
            }
            var collected: [[CalendarEvent]?] = []
            for await events in group { collected.append(events) }
            return collected
        }

        let succeeded = perCalendar.compactMap { $0 }
        // Nothing came back at all — treat as a failed sync, not an empty calendar.
        guard !sources.isEmpty, !succeeded.isEmpty else { return nil }

        let merged = succeeded.flatMap { $0 }.sorted { $0.startDate < $1.startDate }
        return EventCacheData(
            generatedAt: now,
            windowStart: rangeStart,
            windowEnd: rangeEnd,
            sources: sources,
            events: merged
        )
    }

    /// One calendar's events, or nil if the fetch failed (distinct from a genuinely empty
    /// calendar, which returns an empty array — `buildCache` needs to tell those apart).
    private func fetchEvents(
        for source: CalendarSource,
        rangeStart: Date,
        rangeEnd: Date,
        tokenProvider: @escaping AccessTokenProvider
    ) async -> [CalendarEvent]? {
        do {
            let token = try await tokenProvider(source.accountEmail)
            let page = try await api.events(
                calendarId: source.id,
                accessToken: token,
                timeMin: rangeStart,
                timeMax: rangeEnd
            )
            return page.events.compactMap { gcal in
                try? CalendarEvent.from(gcal, calendarId: source.id, colorHex: source.colorHex, calendar: calendar)
            }
        } catch {
            return nil
        }
    }
}

/// Failures that abort a whole sync (as opposed to one calendar).
public enum SyncError: Error, Equatable {
    /// Every calendar's fetch failed — almost always no network or a revoked token.
    case allCalendarsFailed
}
