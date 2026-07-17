import Foundation
import CoreGraphics
import CalCore

/// Builds an `AgendaEntry` from the shared App Group state (event offset + cached events).
/// The agenda is a forward-ordered, gap-free list of events (empty days are skipped); paging
/// moves by whole events, so a day's events can span pages (continuation headers). Every event
/// is shown — the agenda never truncates. How many events fit a page is computed from row
/// heights (`WidgetStyle`) against a height budget, so it varies with content (all-day rows are
/// shorter than timed; each new day adds a header). Does no networking — reads only the cache.
enum AgendaEntryBuilder {
    static func calendar() -> Calendar {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }

    /// All events from today forward through the horizon, in display order (day ascending, then
    /// all-day-first / timed-ascending within a day), paired with the day they're shown under.
    /// Empty days contribute nothing. A multi-day event appears under each day it covers.
    static func orderedEvents(reference: Date, calendar: Calendar, cache: EventCacheData) -> [(day: Date, event: CalendarEvent)] {
        let today = calendar.startOfDay(for: reference)
        var result: [(day: Date, event: CalendarEvent)] = []
        for offset in 0 ..< AppConfig.agendaHorizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayEvents = cache.events.filter { $0.covers(day: day, calendar: calendar) }
            for event in sortedForDay(dayEvents) {
                result.append((day, event))
            }
        }
        return result
    }

    /// All-day first, then timed ascending by start; titles break ties (deterministic).
    static func sortedForDay(_ events: [CalendarEvent]) -> [CalendarEvent] {
        let allDay = events.filter { $0.isAllDay }.sorted { $0.title < $1.title }
        let timed = events.filter { !$0.isAllDay }.sorted {
            $0.startDate != $1.startDate ? $0.startDate < $1.startDate : $0.title < $1.title
        }
        return allDay + timed
    }

    /// How many events (starting at `start`) fit one page's height budget. Each event costs its
    /// row height (all-day vs timed) plus a day-header whenever the day changes — and the first
    /// event on a page always gets a header (its group leads the page, possibly as "(cont)").
    /// Always returns ≥ 1 so a lone oversized event still shows (it just clips).
    static func eventsThatFit(_ ordered: [(day: Date, event: CalendarEvent)], from start: Int) -> Int {
        var used: CGFloat = 0
        var count = 0
        var lastDay: Date?
        var i = start
        while i < ordered.count {
            let (day, event) = ordered[i]
            var cost = event.isAllDay ? WidgetStyle.agendaAllDayRowHeight : WidgetStyle.agendaTimedRowHeight
            if day != lastDay { cost += WidgetStyle.agendaDayHeaderHeight }
            if count > 0 && used + cost > WidgetStyle.agendaPageBudget { break }
            used += cost
            lastDay = day
            count += 1
            i += 1
        }
        return max(count, 1)
    }

    /// Deterministic page-start offsets `[0, f0, f0+f1, …]` walking `eventsThatFit` from 0.
    /// Fixed page starts keep forward/back paging consistent. Always non-empty (`[0]` when there
    /// are no events).
    static func boundaries(_ ordered: [(day: Date, event: CalendarEvent)]) -> [Int] {
        guard !ordered.isEmpty else { return [0] }
        var result: [Int] = []
        var i = 0
        while i < ordered.count {
            result.append(i)
            i += eventsThatFit(ordered, from: i)
        }
        return result
    }

    /// Groups the current page's ordered slice into day-groups, flagging a leading continuation
    /// when the page opens mid-day (the day's header showed on the previous page).
    static func groups(from ordered: [(day: Date, event: CalendarEvent)], offset: Int) -> [AgendaDayGroup] {
        guard offset < ordered.count else { return [] }
        let count = eventsThatFit(ordered, from: offset)
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

    /// Builds an entry from the shared cache. `offsetOverride` lets previews page independently
    /// of the shared offset the widget uses.
    static func live(reference: Date = Date(), offsetOverride: Int? = nil) -> AgendaEntry {
        let cal = calendar()
        let store = AppGroupStore(suiteName: AppConfig.appGroupID)

        guard let cache = EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read() else {
            return AgendaEntry(date: reference, groups: [], canPageBack: false, canPageForward: false, lastSyncedAt: nil)
        }

        let ordered = orderedEvents(reference: reference, calendar: cal, cache: cache)
        let stored = offsetOverride ?? store?.agendaEventOffset ?? 0
        // Snap to the nearest page boundary ≤ the stored offset (it may drift after a re-sync).
        let bounds = boundaries(ordered)
        let start = bounds.last(where: { $0 <= stored }) ?? 0

        return AgendaEntry(
            date: reference,
            groups: groups(from: ordered, offset: start),
            canPageBack: start > 0,
            canPageForward: start < (bounds.last ?? 0), // a later page boundary exists
            lastSyncedAt: cache.generatedAt
        )
    }
}
