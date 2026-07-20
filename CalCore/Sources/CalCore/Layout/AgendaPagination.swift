import Foundation

/// The agenda widgets' page math: turn the cache into a forward-ordered event list, decide
/// where pages break, and slice one page into day groups.
///
/// Lives in CalCore for the same reason `WeekLayout` and `DayCellContent` do — it is a layout
/// *decision* expressed as pure data, with the UI's measurements injected rather than read.
/// That's what lets it be verified by `swift test` and `calcore-check` off-device. The
/// measurements themselves stay in `WidgetStyle`, and the WidgetKit-flavored wrappers
/// (`AgendaEntry`, `AgendaVariant`) stay in the widget extension.
public enum AgendaPagination {

    // MARK: - Ordering

    /// Every event from `reference`'s day forward through `horizonDays`, in display order,
    /// paired with the day it appears under. Empty days contribute nothing, and a multi-day
    /// event appears once under each day it covers.
    ///
    /// Timed events that have already ended are dropped; all-day events and future days are
    /// unaffected.
    public static func orderedEvents(
        reference: Date,
        calendar: Calendar,
        cache: EventCacheData,
        calendarIds: Set<String>? = nil,
        showDeclined: Bool = true,
        horizonDays: Int = AppConfig.agendaHorizonDays
    ) -> [AgendaSlot] {
        let events = cache.visibleEvents(calendarIds: calendarIds, showDeclined: showDeclined)
        guard !events.isEmpty else { return [] }

        let today = calendar.startOfDay(for: reference)

        // Bucket in ONE pass keyed by day, rather than re-filtering the whole event list once
        // per horizon day. `covers(day:calendar:)` performs several `startOfDay` calls, so the
        // old day-by-day scan cost O(days x events) calendar operations on every entry build —
        // and the agenda builds many entries per timeline.
        var byDay: [Date: [CalendarEvent]] = [:]
        let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: today) ?? today
        for event in events {
            var day = max(calendar.startOfDay(for: event.startDate), today)
            let last = event.lastCoveredDay(in: calendar)
            while day <= last && day < horizonEnd {
                byDay[day, default: []].append(event)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        var result: [AgendaSlot] = []
        for offset in 0 ..< horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let dayEvents = byDay[day] else { continue }
            for event in CalendarEvent.displayOrdered(dayEvents) {
                if !event.isAllDay && event.endDate <= reference { continue }
                result.append(AgendaSlot(day: day, event: event))
            }
        }
        return result
    }

    /// The future instants at which the visible set changes — i.e. when a currently-showing
    /// timed event ends — within `after ..< before`. Used to schedule timeline reload points so
    /// an event drops off the moment it's over, with no networking and no refresh-budget cost.
    ///
    /// Filters through the same `visibleEvents` the render path uses, so a hidden event can
    /// never schedule a reload that changes nothing.
    public static func upcomingEndTimes(
        after: Date,
        before: Date,
        cache: EventCacheData,
        calendarIds: Set<String>? = nil,
        showDeclined: Bool = true,
        limit: Int = 12
    ) -> [Date] {
        let ends = cache.visibleEvents(calendarIds: calendarIds, showDeclined: showDeclined)
            .filter { !$0.isAllDay && $0.endDate > after && $0.endDate < before }
            .map(\.endDate)
        // Capped: one entry per event-end is unbounded on a dense day, and WidgetKit holds the
        // whole archived array. The earliest ones matter most — a later reload replaces the rest.
        return Array(Set(ends)).sorted().prefix(limit).map { $0 }
    }

    // MARK: - Paging

    /// Deterministic page-start offsets `[0, f0, f0 + f1, ...]`, walked from 0 so forward and
    /// backward paging always land on the same boundaries. Always non-empty (`[0]` when there
    /// are no events).
    public static func boundaries(_ ordered: [AgendaSlot], sizing: AgendaPageSizing) -> [Int] {
        guard !ordered.isEmpty else { return [0] }
        var result: [Int] = []
        var i = 0
        while i < ordered.count {
            result.append(i)
            i += sizing.eventsThatFit(ordered, from: i)
        }
        return result
    }

    /// The page boundary at or before `offset`. The stored offset can fall between boundaries
    /// after a re-sync changes the event list, so it snaps back rather than rendering a page
    /// that starts mid-boundary.
    public static func pageStart(for offset: Int, in bounds: [Int]) -> Int {
        bounds.last(where: { $0 <= offset }) ?? 0
    }

    /// Steps one page from `offset`, clamped to the ends of the range so paging never produces
    /// a blank page.
    public static func steppedOffset(from offset: Int, direction: Int, bounds: [Int]) -> Int {
        let current = bounds.lastIndex(where: { $0 <= offset }) ?? 0
        let next = min(max(current + direction, 0), bounds.count - 1)
        return bounds[next]
    }

    /// Slices the page beginning at `offset` into day groups, flagging a leading continuation
    /// when the page opens partway through a day whose header already appeared on the previous
    /// page.
    public static func groups(
        from ordered: [AgendaSlot],
        offset: Int,
        sizing: AgendaPageSizing
    ) -> [AgendaDayGroup] {
        guard offset < ordered.count else { return [] }
        let count = sizing.eventsThatFit(ordered, from: offset)
        let slice = ordered[offset ..< min(offset + count, ordered.count)]

        var result: [AgendaDayGroup] = []
        for slot in slice {
            if let last = result.last, last.day == slot.day {
                result[result.count - 1] = AgendaDayGroup(
                    day: last.day,
                    isContinuation: last.isContinuation,
                    events: last.events + [slot.event]
                )
            } else {
                let isContinuation = result.isEmpty && offset > 0 && ordered[offset - 1].day == slot.day
                result.append(AgendaDayGroup(day: slot.day, isContinuation: isContinuation, events: [slot.event]))
            }
        }
        return result
    }
}

/// One event as it appears in the agenda's flat forward list, tagged with the day it renders
/// under. A multi-day event yields one slot per day it covers.
public struct AgendaSlot: Equatable, Sendable {
    public let day: Date
    public let event: CalendarEvent

    public init(day: Date, event: CalendarEvent) {
        self.day = day
        self.event = event
    }
}

/// A day's events on a single agenda page. `isContinuation` marks a day whose header already
/// appeared on the previous page (its events spilled across the boundary), rendered as
/// "Jul 18 (cont)".
public struct AgendaDayGroup: Identifiable, Equatable, Sendable {
    public let day: Date
    public let isContinuation: Bool
    public let events: [CalendarEvent]
    public var id: Date { day }

    public init(day: Date, isContinuation: Bool, events: [CalendarEvent]) {
        self.day = day
        self.isContinuation = isContinuation
        self.events = events
    }
}

/// The rendered row heights the height-fitting page walk costs against, in points.
///
/// Injected rather than read from `WidgetStyle` so this math stays Foundation-only and
/// testable. `WidgetStyle` owns the real numbers and must keep them in step: the walk assumes
/// rows render at exactly these heights, so changing one alone silently mis-paginates.
public struct AgendaMetrics: Equatable, Sendable {
    public let dayHeaderHeight: Double
    public let allDayRowHeight: Double
    public let timedRowHeight: Double
    /// Height available for day groups, after the widget's fixed chrome.
    public let pageBudget: Double

    public init(dayHeaderHeight: Double, allDayRowHeight: Double, timedRowHeight: Double, pageBudget: Double) {
        self.dayHeaderHeight = dayHeaderHeight
        self.allDayRowHeight = allDayRowHeight
        self.timedRowHeight = timedRowHeight
        self.pageBudget = pageBudget
    }
}

/// How many events fit one agenda page — the one thing that genuinely differs between the two
/// agenda widgets.
public enum AgendaPageSizing: Equatable, Sendable {
    /// Small widget: a greedy walk costing each row by its rendered height (all-day rows are
    /// shorter than timed, and each new day adds a header) against a height budget. Capacity
    /// therefore varies with content.
    case heightFit(AgendaMetrics)
    /// Medium widget: uniform two-line cards with no per-day header in the event column, so a
    /// page is simply a constant number of events.
    case fixedCount(Int)

    /// How many events, starting at `start`, fit one page. Always at least 1, so a single
    /// oversized event still renders (clipped) instead of producing an empty page forever.
    public func eventsThatFit(_ ordered: [AgendaSlot], from start: Int) -> Int {
        switch self {
        case .fixedCount(let n):
            return max(min(n, ordered.count - start), 1)
        case .heightFit(let metrics):
            var used = 0.0
            var count = 0
            var lastDay: Date?
            var i = start
            while i < ordered.count {
                let slot = ordered[i]
                var cost = slot.event.isAllDay ? metrics.allDayRowHeight : metrics.timedRowHeight
                if slot.day != lastDay { cost += metrics.dayHeaderHeight }
                if count > 0 && used + cost > metrics.pageBudget { break }
                used += cost
                lastDay = slot.day
                count += 1
                i += 1
            }
            return max(count, 1)
        }
    }
}
