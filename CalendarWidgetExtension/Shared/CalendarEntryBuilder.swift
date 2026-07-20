import Foundation
import CalCore

/// Builds a `CalendarTimelineEntry` from the shared App Group state (pagination offset +
/// cached events). Drives the installed widget's timeline. Does no networking — reads only
/// the cache.
enum CalendarEntryBuilder {
    static func calendar() -> Calendar { .calWidget }

    /// Buckets events into the window's days (an event lands in every day it covers).
    ///
    /// Walks each event's own span once instead of re-filtering the whole event list per day.
    /// `covers(day:calendar:)` runs several `startOfDay` calls, so the per-day scan cost
    /// O(days x events) calendar operations every time the grid rebuilt.
    static func groupByDay(events: [CalendarEvent], window: DateWindow, calendar: Calendar) -> [Date: [CalendarEvent]] {
        guard let first = window.days.first, let last = window.days.last else { return [:] }
        var result: [Date: [CalendarEvent]] = [:]
        for day in window.days { result[day] = [] } // every day present, even when empty
        for event in events {
            var day = max(calendar.startOfDay(for: event.startDate), first)
            let end = min(event.lastCoveredDay(in: calendar), last)
            while day <= end {
                result[day]?.append(event)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return result
    }

    /// Builds an entry from the shared cache, scoped to this widget instance's `calendarIds`
    /// (nil ⇒ show every calendar). When there's no cache, returns an *empty* entry (honest
    /// "no data" state) rather than sample fixtures — samples are reserved for the widget
    /// placeholder, the gallery snapshot, the in-app preview, and Xcode previews.
    /// `offsetOverride` lets a caller page independently of the shared offset the widget uses.
    static func live(weekCount: Int, calendarIds: Set<String>? = nil, showDeclined: Bool = false, reference: Date = Date(), offsetOverride: Int? = nil) -> CalendarTimelineEntry {
        let cal = calendar()
        let store = AppGroupStore(suiteName: AppConfig.appGroupID)
        let offset = offsetOverride ?? store?.twoWeekPageOffset ?? 0
        let isSyncing = store?.isSyncing ?? false
        let window = DateWindow(referenceDate: reference, pageOffset: offset, weekCount: weekCount, calendar: cal)

        let cache = EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read()
        // A non-nil, empty selection means the widget hasn't been configured yet (nil = show
        // all). Prompt to configure — but only once synced, so a
        // never-synced widget still shows the sign-in prompt.
        let needsConfiguration = calendarIds?.isEmpty == true && cache != nil
        let events = cache?.visibleEvents(calendarIds: calendarIds, showDeclined: showDeclined) ?? []
        return CalendarTimelineEntry(
            date: reference,
            window: window,
            eventsByDay: cache == nil ? [:] : groupByDay(events: events, window: window, calendar: cal),
            cacheIsStale: cache.map { !$0.covers(start: window.startDate, end: window.endExclusive) } ?? true,
            isSyncing: isSyncing,
            lastSyncedAt: cache?.generatedAt,
            needsConfiguration: needsConfiguration
        )
    }
}
