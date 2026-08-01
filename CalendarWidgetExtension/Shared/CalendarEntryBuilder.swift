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

    /// Builds an entry from the shared cache, scoped to this widget instance's `refs`
    /// (nil ⇒ show every calendar). When there's no cache, returns an *empty* entry (honest
    /// "no data" state) rather than sample fixtures — samples are reserved for the widget
    /// placeholder, the gallery snapshot, the in-app preview, and Xcode previews.
    /// `offsetOverride` lets a caller page independently of the shared offset the widget uses.
    ///
    /// `cache` may be supplied by a caller that already read it — the timeline provider gets one
    /// back from `CoverageRefresh` when it syncs, and re-decoding the file to build the entry
    /// from the same bytes is pure waste inside a memory-capped extension.
    static func live(
        weekCount: Int,
        refs: Set<CalendarRef>? = nil,
        hasUnresolvableSelection: Bool = false,
        showDeclined: Bool = false,
        reference: Date = Date(),
        offsetOverride: Int? = nil,
        cache preloaded: EventCacheData? = nil
    ) -> CalendarTimelineEntry {
        let cal = calendar()
        let store = AppGroupStore(suiteName: AppConfig.appGroupID)
        let offset = offsetOverride ?? store?.twoWeekPageOffset ?? 0
        let isSyncing = store?.isSyncing ?? false
        let window = DateWindow(referenceDate: reference, pageOffset: offset, weekCount: weekCount, calendar: cal)

        let cache = preloaded ?? EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read()
        let needsConfiguration = EventCacheData.needsConfiguration(
            refs: refs,
            hasUnresolvable: hasUnresolvableSelection,
            catalog: CatalogStore(appGroupIdentifier: AppConfig.appGroupID)?.read()
        )
        let events = cache?.visibleEvents(refs: refs, showDeclined: showDeclined) ?? []
        // Stale means "short of what this instance asked for", which is a range *and* a calendar
        // set — a newly selected calendar isn't in the cache no matter how fresh the dates are.
        let isStale = cache.map {
            !$0.covers(start: window.startDate, end: window.endExclusive) || !$0.covers(refs: refs ?? [])
        } ?? true
        return CalendarTimelineEntry(
            date: reference,
            window: window,
            eventsByDay: cache == nil ? [:] : groupByDay(events: events, window: window, calendar: cal),
            cacheIsStale: isStale,
            isSyncing: isSyncing,
            lastSyncedAt: cache?.generatedAt,
            needsConfiguration: needsConfiguration
        )
    }
}
