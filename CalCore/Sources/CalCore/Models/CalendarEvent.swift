import Foundation

/// A flattened, denormalized event ready for fast widget rendering.
/// Color is copied from the source calendar at cache-write time so the widget
/// never needs a join. Produced by the sync layer, consumed by the widget.
public struct CalendarEvent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    /// FK to `CalendarSource.id`.
    public let calendarId: String
    public let title: String
    /// For timed events: the actual start instant. For all-day: start-of-day.
    public let startDate: Date
    /// For timed events: the actual end instant. For all-day: the *exclusive*
    /// end-of-span (start-of-day of the day after the last covered day), mirroring
    /// Google's `end.date` semantics. Use `lastCoveredDay(in:)` for the inclusive day.
    public let endDate: Date
    public let isAllDay: Bool
    /// Denormalized copy of the source calendar's color, e.g. "#7986CB".
    public let colorHex: String

    public init(
        id: String,
        calendarId: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        colorHex: String
    ) {
        self.id = id
        self.calendarId = calendarId
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.colorHex = colorHex
    }

    /// The last calendar day this event covers, inclusive. For all-day events the
    /// stored `endDate` is exclusive (Google's convention), so this steps back one day.
    public func lastCoveredDay(in calendar: Calendar) -> Date {
        guard isAllDay else { return calendar.startOfDay(for: endDate) }
        let startOfEnd = calendar.startOfDay(for: endDate)
        // If end is exactly midnight and after start-of-day, the last covered day is the prior day.
        if startOfEnd > calendar.startOfDay(for: startDate) {
            return calendar.date(byAdding: .day, value: -1, to: startOfEnd) ?? startOfEnd
        }
        return startOfEnd
    }

    /// Whether this event covers the given calendar day (compared at day granularity).
    public func covers(day: Date, calendar: Calendar) -> Bool {
        let target = calendar.startOfDay(for: day)
        let firstDay = calendar.startOfDay(for: startDate)
        let lastDay = lastCoveredDay(in: calendar)
        return target >= firstDay && target <= lastDay
    }
}
