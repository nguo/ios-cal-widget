import Foundation

/// A flattened, denormalized event ready for fast widget rendering.
/// Color is copied from the source calendar at cache-write time so the widget
/// never needs a join. Produced by the sync layer, consumed by the widget.
public struct CalendarEvent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    /// Google's calendarId. Not a key on its own — it repeats across accounts, so pair it with
    /// `accountEmail` via `ref`.
    public let calendarId: String
    /// The signed-in account this event was fetched through.
    public let accountEmail: String
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
    /// Google's canonical event link (`event.htmlLink` from the API), e.g.
    /// "https://www.google.com/calendar/event?eid=...". Used to deep-link the agenda widget to the
    /// exact event — the `eid` it carries is Google's own, avoiding fragile hand-encoding. Optional
    /// so events cached before this field existed (and non-Google sources) still decode.
    public let htmlLink: String?
    /// True when the signed-in user has declined this event (their attendee `responseStatus` is
    /// "declined"). Cached for every event; each widget decides whether to hide declined events or
    /// show them struck through. Optional in the wire format so caches written before this field
    /// existed still decode (see `init(from:)`).
    public let isDeclined: Bool

    public init(
        id: String,
        calendarId: String,
        accountEmail: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        colorHex: String,
        htmlLink: String? = nil,
        isDeclined: Bool = false
    ) {
        self.id = id
        self.calendarId = calendarId
        self.accountEmail = accountEmail
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.colorHex = colorHex
        self.htmlLink = htmlLink
        self.isDeclined = isDeclined
    }

    private enum CodingKeys: String, CodingKey {
        case id, calendarId, accountEmail, title, startDate, endDate, isAllDay, colorHex, htmlLink, isDeclined
    }

    /// Custom decode so `htmlLink` and `isDeclined` — both added after the cache format shipped —
    /// tolerate older caches that omit them. Encoding stays synthesized.
    ///
    /// `accountEmail` is deliberately **not** given that treatment. A pre-multi-account cache has
    /// no account on its events, and any default we invented would attribute them to an account
    /// that may not own them. Requiring it makes the whole file fail to decode, `read()` returns
    /// nil, and the next sync repopulates — which is the migration, and why there is no migration
    /// code.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        calendarId = try c.decode(String.self, forKey: .calendarId)
        accountEmail = try c.decode(String.self, forKey: .accountEmail)
        title = try c.decode(String.self, forKey: .title)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        isAllDay = try c.decode(Bool.self, forKey: .isAllDay)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        htmlLink = try c.decodeIfPresent(String.self, forKey: .htmlLink)
        isDeclined = try c.decodeIfPresent(Bool.self, forKey: .isDeclined) ?? false
    }

    /// Identity of an event *within the cache*. `id` alone is not it: Google's event id is unique
    /// only within a calendar, and the same meeting reachable through two calendars comes back
    /// once per calendar carrying the same `id`. Those are two rows the widget draws separately
    /// (each in its own calendar's color), so anything that de-dupes or keys events must use the
    /// full triple — de-duping on `id` collapses them to one, and "incoming wins" then leaves the
    /// survivor showing whichever calendar's color arrived last.
    ///
    /// The account is part of it for the same reason one level up: a meeting on a calendar shared
    /// with two of your accounts comes back once per account under one `(calendarId, id)`.
    ///
    /// Same root cause as the "never key a `ForEach` on `CalendarEvent.id`" rule.
    public struct CacheKey: Hashable, Sendable {
        public let ref: CalendarRef
        public let id: String

        public init(ref: CalendarRef, id: String) {
            self.ref = ref
            self.id = id
        }
    }

    public var ref: CalendarRef { CalendarRef(accountEmail: accountEmail, calendarId: calendarId) }

    public var cacheKey: CacheKey { CacheKey(ref: ref, id: id) }

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
