import Foundation
@testable import CalCore

enum TestSupport {
    /// Deterministic Gregorian calendar in a fixed timezone, Sunday-first.
    static func calendar(tz: String = "America/Los_Angeles") -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 1
        return cal
    }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, calendar: Calendar) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        return calendar.date(from: c)!
    }

    static func event(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        color: String = "#000000",
        calendarId: String = "cal1"
    ) -> CalendarEvent {
        CalendarEvent(
            id: id, calendarId: calendarId, title: title,
            startDate: start, endDate: end, isAllDay: isAllDay, colorHex: color
        )
    }
}
