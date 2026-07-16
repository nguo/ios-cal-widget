import Foundation

/// Wire-format types for the Google Calendar REST API, plus the mapping into our flat
/// `CalendarEvent`. Only the fields we use are modeled.

// MARK: - calendarList.list

public struct GCalCalendarListResponse: Codable, Sendable {
    public let items: [GCalCalendarListEntry]
    public let nextPageToken: String?
}

public struct GCalCalendarListEntry: Codable, Sendable {
    public let id: String
    public let summary: String?
    public let backgroundColor: String?
    public let primary: Bool?
}

// MARK: - events.list

public struct GCalEventsResponse: Codable, Sendable {
    public let items: [GCalEvent]
    public let nextPageToken: String?
    public let nextSyncToken: String?
}

public struct GCalEvent: Codable, Sendable {
    public let id: String
    public let summary: String?
    public let start: GCalEventDateTime?
    public let end: GCalEventDateTime?
    /// "confirmed" | "tentative" | "cancelled".
    public let status: String?
}

/// Google represents a boundary as EITHER `date` (all-day, no time) OR `dateTime` (timed).
public struct GCalEventDateTime: Codable, Sendable {
    public let date: String?      // "2026-07-15"
    public let dateTime: String?  // "2026-07-15T16:00:00-07:00"
    public let timeZone: String?
}

// MARK: - Mapping

public enum GCalMappingError: Error, Equatable {
    case missingStartOrEnd
    case unparseableDate(String)
}

public extension CalendarEvent {

    /// Detect all-day the canonical way: a `date` present with no `dateTime`.
    static func isAllDay(_ dt: GCalEventDateTime) -> Bool {
        dt.date != nil && dt.dateTime == nil
    }

    /// Maps a Google event into our flat model.
    /// - Cancelled events return nil (caller should skip them).
    /// - All-day `end.date` is exclusive per Google's spec; we store it as-is and rely on
    ///   `CalendarEvent.lastCoveredDay` to step back for the inclusive last day.
    static func from(
        _ gcal: GCalEvent,
        calendarId: String,
        colorHex: String,
        calendar: Calendar
    ) throws -> CalendarEvent? {
        if gcal.status == "cancelled" { return nil }
        guard let start = gcal.start, let end = gcal.end else {
            throw GCalMappingError.missingStartOrEnd
        }

        let allDay = isAllDay(start)
        let startDate: Date
        let endDate: Date

        if allDay {
            guard let s = parseAllDay(start.date, calendar: calendar) else {
                throw GCalMappingError.unparseableDate(start.date ?? "nil")
            }
            // end may be a date (normal all-day) or, defensively, fall back to start+1 day.
            let e = parseAllDay(end.date, calendar: calendar)
                ?? calendar.date(byAdding: .day, value: 1, to: s)!
            startDate = s
            endDate = e
        } else {
            guard let s = parseDateTime(start.dateTime) else {
                throw GCalMappingError.unparseableDate(start.dateTime ?? "nil")
            }
            guard let e = parseDateTime(end.dateTime) else {
                throw GCalMappingError.unparseableDate(end.dateTime ?? "nil")
            }
            startDate = s
            endDate = e
        }

        return CalendarEvent(
            id: gcal.id,
            calendarId: calendarId,
            title: gcal.summary ?? "(No title)",
            startDate: startDate,
            endDate: endDate,
            isAllDay: allDay,
            colorHex: colorHex
        )
    }

    /// Parse an all-day "yyyy-MM-dd" into start-of-day in the given calendar's timezone.
    static func parseAllDay(_ string: String?, calendar: Calendar) -> Date? {
        guard let string else { return nil }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: string) else { return nil }
        return calendar.startOfDay(for: d)
    }

    /// Parse an RFC3339 timestamp (with or without fractional seconds).
    static func parseDateTime(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
