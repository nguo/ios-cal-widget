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
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let hour24 = comps.hour ?? 0
        let minute = comps.minute ?? 0

        let isPM = hour24 >= 12
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 } // 0 and 12 both display as 12
        let suffix = isPM ? "p" : "a"

        if minute == 0 {
            return "\(hour12)\(suffix)"
        }
        return "\(hour12):\(String(format: "%02d", minute))\(suffix)"
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
