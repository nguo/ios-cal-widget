import Foundation

/// Resolves which rows a day cell shows, applying the "3 events + smart 4th line" rule:
/// - <= maxRows events: show them all
/// - > maxRows events: show the first (maxRows - 1), then a "+N more" row
///
/// All-day events sort first (they render as colored bars), then timed events by start time.
/// Kept out of the SwiftUI view so it can be unit-tested.
public struct DayCellContent: Equatable, Sendable {
    public enum Row: Equatable, Sendable {
        case event(CalendarEvent)
        case moreCount(Int)
    }

    public let rows: [Row]

    public static let defaultMaxRows = 4

    public init(events: [CalendarEvent], calendar: Calendar, maxRows: Int = defaultMaxRows) {
        let sorted = Self.sort(events, calendar: calendar)

        guard sorted.count > maxRows else {
            self.rows = sorted.map { .event($0) }
            return
        }
        // Overflow: show (maxRows - 1) events, then a "+N more" summarizing the rest.
        let shown = Array(sorted.prefix(maxRows - 1))
        let remaining = sorted.count - shown.count
        self.rows = shown.map { .event($0) } + [.moreCount(remaining)]
    }

    /// All-day first, then timed ascending by start; titles break ties for determinism.
    static func sort(_ events: [CalendarEvent], calendar: Calendar) -> [CalendarEvent] {
        let allDay = events.filter { $0.isAllDay }.sorted { $0.title < $1.title }
        let timed = events.filter { !$0.isAllDay }.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.title < $1.title
        }
        return allDay + timed
    }
}
