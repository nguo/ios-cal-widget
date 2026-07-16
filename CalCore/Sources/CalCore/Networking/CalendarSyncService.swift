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

    /// Builds the canonical cache for the given range across all selected sources.
    /// Fetches calendars concurrently. A per-calendar failure is skipped (its events are
    /// omitted) rather than failing the whole sync — partial data beats no data, and the
    /// atomic write means the previous cache survives if the caller decides to abort.
    public func buildCache(
        sources: [CalendarSource],
        rangeStart: Date,
        rangeEnd: Date,
        now: Date,
        tokenProvider: @escaping AccessTokenProvider
    ) async -> EventCacheData {
        let selected = sources.filter { $0.isSelected }

        let perCalendar: [[CalendarEvent]] = await withTaskGroup(of: [CalendarEvent].self) { group in
            for source in selected {
                group.addTask {
                    await self.fetchEvents(for: source, rangeStart: rangeStart, rangeEnd: rangeEnd, tokenProvider: tokenProvider)
                }
            }
            var collected: [[CalendarEvent]] = []
            for await events in group { collected.append(events) }
            return collected
        }

        let merged = perCalendar.flatMap { $0 }.sorted { $0.startDate < $1.startDate }
        return EventCacheData(
            generatedAt: now,
            windowStart: rangeStart,
            windowEnd: rangeEnd,
            sources: selected,
            events: merged
        )
    }

    private func fetchEvents(
        for source: CalendarSource,
        rangeStart: Date,
        rangeEnd: Date,
        tokenProvider: @escaping AccessTokenProvider
    ) async -> [CalendarEvent] {
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
            return [] // skip this calendar on failure; other calendars still populate
        }
    }
}
