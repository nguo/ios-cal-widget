import Foundation
import CalCore

/// Builds an `AgendaEntry` from the shared App Group state (event offset + cached events).
/// The agenda is a forward-ordered, gap-free list of events (empty days are skipped); paging
/// moves by whole events, so a day's events can span pages (continuation headers). Every event
/// is shown — the agenda never truncates. How many events fit a page is decided by the widget
/// variant's `AgendaPageSizing`. Does no networking — reads only the cache.
enum AgendaEntryBuilder {
    static func calendar() -> Calendar {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }

    /// All events from today forward through the horizon, in display order (day ascending, then
    /// all-day-first / timed-ascending within a day), paired with the day they're shown under.
    /// Empty days contribute nothing. A multi-day event appears under each day it covers.
    /// `calendarIds` restricts to that per-widget selection (nil ⇒ every calendar in the cache).
    /// `showDeclined` keeps declined events in the list (they render struck through); when false
    /// they're dropped entirely.
    static func orderedEvents(
        reference: Date,
        calendar: Calendar,
        cache: EventCacheData,
        calendarIds: Set<String>? = nil,
        showDeclined: Bool = true
    ) -> [(day: Date, event: CalendarEvent)] {
        let today = calendar.startOfDay(for: reference)
        var events = calendarIds.map { ids in cache.events.filter { ids.contains($0.calendarId) } } ?? cache.events
        if !showDeclined { events = events.filter { !$0.isDeclined } }
        var result: [(day: Date, event: CalendarEvent)] = []
        for offset in 0 ..< AppConfig.agendaHorizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayEvents = events.filter { $0.covers(day: day, calendar: calendar) }
            for event in sortedForDay(dayEvents) {
                // Hide timed events that have already ended (all-day + future days unaffected).
                if !event.isAllDay && event.endDate <= reference { continue }
                result.append((day, event))
            }
        }
        return result
    }

    /// The instants between `after` and `before` at which a currently-visible timed event ends —
    /// i.e. the future moments the agenda's contents change. Used to schedule timeline reload points
    /// so an event drops off the widget the minute it's over. Sorted ascending, deduplicated.
    /// `calendarIds` scopes to the widget's selection so reloads track only its visible events;
    /// `showDeclined` mirrors the render filter so a hidden declined event doesn't schedule a reload.
    static func upcomingEndTimes(after: Date, before: Date, cache: EventCacheData, calendarIds: Set<String>? = nil, showDeclined: Bool = true) -> [Date] {
        let ends = cache.events
            .filter { calendarIds?.contains($0.calendarId) ?? true }
            .filter { showDeclined || !$0.isDeclined }
            .filter { !$0.isAllDay && $0.endDate > after && $0.endDate < before }
            .map(\.endDate)
        return Array(Set(ends)).sorted()
    }

    /// All-day first, then timed ascending by start; titles break ties (deterministic).
    static func sortedForDay(_ events: [CalendarEvent]) -> [CalendarEvent] {
        let allDay = events.filter { $0.isAllDay }.sorted { $0.title < $1.title }
        let timed = events.filter { !$0.isAllDay }.sorted {
            $0.startDate != $1.startDate ? $0.startDate < $1.startDate : $0.title < $1.title
        }
        return allDay + timed
    }

    /// Deterministic page-start offsets `[0, f0, f0+f1, …]` walking the variant's page sizing
    /// from 0. Fixed page starts keep forward/back paging consistent. Always non-empty (`[0]`
    /// when there are no events).
    static func boundaries(_ ordered: [(day: Date, event: CalendarEvent)], sizing: AgendaPageSizing = .heightFit) -> [Int] {
        guard !ordered.isEmpty else { return [0] }
        var result: [Int] = []
        var i = 0
        while i < ordered.count {
            result.append(i)
            i += sizing.eventsThatFit(ordered, from: i)
        }
        return result
    }

    /// Groups the current page's ordered slice into day-groups, flagging a leading continuation
    /// when the page opens mid-day (the day's header showed on the previous page).
    static func groups(from ordered: [(day: Date, event: CalendarEvent)], offset: Int, sizing: AgendaPageSizing = .heightFit) -> [AgendaDayGroup] {
        guard offset < ordered.count else { return [] }
        let count = sizing.eventsThatFit(ordered, from: offset)
        let slice = ordered[offset ..< min(offset + count, ordered.count)]

        var result: [AgendaDayGroup] = []
        for pair in slice {
            if let last = result.last, last.day == pair.day {
                result[result.count - 1] = AgendaDayGroup(
                    day: last.day, isContinuation: last.isContinuation, events: last.events + [pair.event]
                )
            } else {
                // A leading group is a continuation when the prior event (previous page) shares its day.
                let isContinuation = result.isEmpty && offset > 0 && ordered[offset - 1].day == pair.day
                result.append(AgendaDayGroup(day: pair.day, isContinuation: isContinuation, events: [pair.event]))
            }
        }
        return result
    }

    /// Builds an entry from the shared cache, scoped to this widget instance's `calendarIds`
    /// (nil ⇒ show every calendar). `variant` selects which widget's stored page offset and page
    /// sizing to use. `offsetOverride` lets previews page independently of the stored offset.
    static func live(calendarIds: Set<String>? = nil, showDeclined: Bool = false, variant: AgendaVariant = .small, reference: Date = Date(), offsetOverride: Int? = nil) -> AgendaEntry {
        let cal = calendar()
        let store = AppGroupStore(suiteName: AppConfig.appGroupID)
        let cache = EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read()
        // A non-nil, empty selection means the widget hasn't been configured yet (nil = show all,
        // used by previews). Prompt to configure — but only once synced, so a never-synced widget
        // still shows the sign-in prompt (you can't pick calendars before they exist).
        let needsConfiguration = calendarIds?.isEmpty == true && cache != nil

        guard let cache, !needsConfiguration else {
            return AgendaEntry(
                date: reference, groups: [], canPageBack: false, canPageForward: false,
                lastSyncedAt: cache?.generatedAt, calendarIds: calendarIds,
                showDeclined: showDeclined, needsConfiguration: needsConfiguration
            )
        }

        let ordered = orderedEvents(reference: reference, calendar: cal, cache: cache, calendarIds: calendarIds, showDeclined: showDeclined)
        let sizing = variant.pageSizing
        let stored = offsetOverride ?? store.map { variant.eventOffset(in: $0) } ?? 0
        // Snap to the nearest page boundary ≤ the stored offset (it may drift after a re-sync).
        let bounds = boundaries(ordered, sizing: sizing)
        let start = bounds.last(where: { $0 <= stored }) ?? 0

        return AgendaEntry(
            date: reference,
            groups: groups(from: ordered, offset: start, sizing: sizing),
            canPageBack: start > 0,
            canPageForward: start < (bounds.last ?? 0), // a later page boundary exists
            lastSyncedAt: cache.generatedAt,
            calendarIds: calendarIds,
            showDeclined: showDeclined,
            needsConfiguration: false
        )
    }
}
