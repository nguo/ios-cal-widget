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
        calendarId: String = "cal1",
        accountEmail: String = "a@example.com"
    ) -> CalendarEvent {
        CalendarEvent(
            id: id, calendarId: calendarId, accountEmail: accountEmail, title: title,
            startDate: start, endDate: end, isAllDay: isAllDay, colorHex: color
        )
    }

    static func ref(_ calendarId: String, account: String = "a@example.com") -> CalendarRef {
        CalendarRef(accountEmail: account, calendarId: calendarId)
    }

    static func source(
        _ calendarId: String,
        account: String = "a@example.com",
        summary: String = "Cal",
        color: String = "#000000"
    ) -> CalendarSource {
        CalendarSource(id: calendarId, accountEmail: account, summary: summary, colorHex: color)
    }

    static func catalog(_ sources: [CalendarSource], generatedAt: Date = Date()) -> CalendarCatalog {
        CalendarCatalog(generatedAt: generatedAt, sources: sources)
    }
}
