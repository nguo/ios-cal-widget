import Foundation

/// Produces the compact per-event text shown in a day cell, e.g. "4p Party",
/// "5:30p Meeting". All-day events have no time prefix (rendered as a bar instead).
public enum EventTextFormatter {

    /// Compact time prefix for a timed event: 12-hour, lowercase single-letter am/pm,
    /// minutes omitted when :00. Noon -> "12p", midnight -> "12a".
    /// Returns nil for all-day events.
    public static func timePrefix(for event: CalendarEvent, calendar: Calendar) -> String? {
        guard !event.isAllDay else { return nil }
        return timePrefix(for: event.startDate, calendar: calendar)
    }

    /// Compact time prefix for a date, e.g. 16:00 -> "4p", 17:30 -> "5:30p", 9:05 -> "9:05a".
    public static func timePrefix(for date: Date, calendar: Calendar) -> String {
        clock(for: date, calendar: calendar, meridiem: true)
    }

    /// Compact 12-hour clock time, minutes omitted when :00. With `meridiem`, appends a
    /// single-letter am/pm ("9:30a", "4p"); without it, bare ("9:30", "4"). Noon/midnight -> 12.
    public static func clock(for date: Date, calendar: Calendar, meridiem: Bool) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let hour24 = comps.hour ?? 0
        let minute = comps.minute ?? 0

        let isPM = hour24 >= 12
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 } // 0 and 12 both display as 12
        let suffix = meridiem ? (isPM ? "p" : "a") : ""

        if minute == 0 {
            return "\(hour12)\(suffix)"
        }
        return "\(hour12):\(String(format: "%02d", minute))\(suffix)"
    }

    /// Start–end time range for a timed event, e.g. "9:30-10a", "9-10:30p". Only the *end*
    /// carries the am/pm letter (the start's is implied). Not meaningful for all-day events.
    public static func timeRange(for event: CalendarEvent, calendar: Calendar) -> String {
        let start = clock(for: event.startDate, calendar: calendar, meridiem: false)
        let end = clock(for: event.endDate, calendar: calendar, meridiem: true)
        return "\(start)-\(end)"
    }

    /// The full single-line label for a timed event ("4p Party") or the bare title
    /// for an all-day event (which is rendered inside a colored bar).
    public static func line(for event: CalendarEvent, calendar: Calendar) -> String {
        if let prefix = timePrefix(for: event, calendar: calendar) {
            return "\(prefix) \(event.title)"
        }
        return event.title
    }
}
