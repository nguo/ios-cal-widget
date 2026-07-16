import Foundation
import CalCore

/// Builds a `CalendarTimelineEntry` from the shared App Group state (pagination offset +
/// cached events). Used by both the widget's timeline provider and the app's in-app preview
/// so they render identically. Falls back to sample fixtures when there's no cache yet
/// (e.g. before the first sync), so previews are never blank.
enum CalendarEntryBuilder {
    static func calendar() -> Calendar {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }

    /// Buckets events into the window's days (an event lands in every day it covers).
    static func groupByDay(events: [CalendarEvent], window: DateWindow, calendar: Calendar) -> [Date: [CalendarEvent]] {
        var result: [Date: [CalendarEvent]] = [:]
        for day in window.days {
            result[day] = events.filter { $0.covers(day: day, calendar: calendar) }
        }
        return result
    }

    /// Builds an entry from the shared cache. When there's no cache, returns an *empty* entry
    /// (honest "no data" state) rather than sample fixtures — samples are reserved for the
    /// widget placeholder / Xcode previews. `offsetOverride` lets the in-app preview page
    /// independently of the shared offset the widget uses.
    static func live(weekCount: Int, reference: Date = Date(), offsetOverride: Int? = nil) -> CalendarTimelineEntry {
        let cal = calendar()
        let store = AppGroupStore(suiteName: AppConfig.appGroupID)
        let offset = offsetOverride ?? store?.pageOffset ?? 0
        let isSyncing = store?.isSyncing ?? false
        let window = DateWindow(referenceDate: reference, pageOffset: offset, weekCount: weekCount, calendar: cal)

        let cache = EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read()
        return CalendarTimelineEntry(
            date: reference,
            window: window,
            eventsByDay: cache.map { groupByDay(events: $0.events, window: window, calendar: cal) } ?? [:],
            cacheIsStale: cache.map { !$0.covers(start: window.startDate, end: window.endExclusive) } ?? true,
            isSyncing: isSyncing,
            lastSyncedAt: cache?.generatedAt
        )
    }
}
