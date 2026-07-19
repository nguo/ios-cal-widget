import Foundation
import CalCore

/// Builds a `CalendarTimelineEntry` from the shared App Group state (pagination offset +
/// cached events). Drives the installed widget's timeline. Does no networking — reads only
/// the cache.
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
        let events: [CalendarEvent] = cache.map { c in
            var e = calendarIds.map { ids in c.events.filter { ids.contains($0.calendarId) } } ?? c.events
            if !showDeclined { e = e.filter { !$0.isDeclined } }
            return e
        } ?? []
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
