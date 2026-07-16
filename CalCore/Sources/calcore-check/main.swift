import Foundation
import CalCore

// Lightweight assertion harness so CalCore's critical logic can be verified without
// Xcode/XCTest. Mirrors the XCTest suite's key cases. Exits non-zero on any failure.

var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition {
        failures += 1
        print("  ❌ \(message)")
    }
}

func eq<T: Equatable>(_ a: T, _ b: T, _ message: String) {
    check(a == b, "\(message) — got \(a), expected \(b)")
}

func makeCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    c.locale = Locale(identifier: "en_US_POSIX")
    c.firstWeekday = 1
    return c
}

let cal = makeCalendar()

/// Build a date in the fixed test calendar. Uses the global `cal`.
func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    var c = DateComponents(); c.year = y; c.month = m; c.day = day; c.hour = h; c.minute = mi
    return cal.date(from: c)!
}

func ev(_ id: String, _ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEvent {
    CalendarEvent(id: id, calendarId: "c", title: title, startDate: start, endDate: end, isAllDay: allDay, colorHex: "#000")
}

// MARK: DateWindow
do {
    let ref = d(2026, 3, 16, 12)
    let w = DateWindow(referenceDate: ref, pageOffset: 0, weekCount: 2, calendar: cal)
    eq(w.days.count, 14, "two-week window has 14 days")
    eq(cal.component(.weekday, from: w.startDate), 1, "window starts on Sunday")
    check(w.days.contains(cal.startOfDay(for: ref)), "offset-0 window contains today")
    let next = DateWindow(referenceDate: ref, pageOffset: 1, weekCount: 2, calendar: cal)
    eq(cal.dateComponents([.day], from: w.startDate, to: next.startDate).day!, 14, "forward page shifts 14 days")
    eq(next.days.first!, w.endExclusive, "next window abuts current")
    let prev = DateWindow(referenceDate: ref, pageOffset: -1, weekCount: 2, calendar: cal)
    eq(cal.dateComponents([.day], from: prev.startDate, to: w.startDate).day!, 14, "back page shifts -14 days")
    eq(w.monthLabel(calendar: cal, locale: Locale(identifier: "en_US")), "MARCH", "month label")
}

// MARK: EventTextFormatter
do {
    eq(EventTextFormatter.timePrefix(for: d(2026, 3, 16, 16, 0), calendar: cal), "4p", "16:00 -> 4p")
    eq(EventTextFormatter.timePrefix(for: d(2026, 3, 16, 17, 30), calendar: cal), "5:30p", "17:30 -> 5:30p")
    eq(EventTextFormatter.timePrefix(for: d(2026, 3, 16, 9, 5), calendar: cal), "9:05a", "9:05 -> 9:05a")
    eq(EventTextFormatter.timePrefix(for: d(2026, 3, 16, 12, 0), calendar: cal), "12p", "noon -> 12p")
    eq(EventTextFormatter.timePrefix(for: d(2026, 3, 16, 0, 0), calendar: cal), "12a", "midnight -> 12a")
    let s = d(2026, 3, 16, 16, 0)
    eq(EventTextFormatter.line(for: ev("1", "Party", s, s), calendar: cal), "4p Party", "timed line")
}

// MARK: DayCellContent
do {
    func timed(_ id: String, _ hour: Int) -> CalendarEvent {
        let s = d(2026, 3, 16, hour, 0)
        return ev(id, "E\(id)", s, s)
    }
    eq(DayCellContent(events: [timed("1", 9), timed("2", 10), timed("3", 11)], calendar: cal).rows.count, 3, "3 events -> 3 rows")
    let four = DayCellContent(events: (1...4).map { timed("\($0)", 8 + $0) }, calendar: cal)
    eq(four.rows.count, 4, "4 events -> 4 rows")
    check(four.rows.allSatisfy { if case .event = $0 { return true } else { return false } }, "4 events all shown, no +more")
    let five = DayCellContent(events: (1...5).map { timed("\($0)", 8 + $0) }, calendar: cal)
    eq(five.rows.count, 4, "5 events -> 4 rows")
    eq(five.rows.last, .moreCount(2), "5 events -> +2 more")
    let allDayStart = d(2026, 3, 16, 0, 0)
    let allDay = ev("h", "Holiday", allDayStart, allDayStart, allDay: true)
    if case let .event(first) = DayCellContent(events: [timed("1", 9), allDay], calendar: cal).rows.first {
        check(first.isAllDay, "all-day sorts first")
    } else { check(false, "expected an event row first") }
}

// MARK: DeepLinkBuilder
do {
    eq(DeepLinkBuilder.dayURL(for: d(2026, 7, 5, 12, 0), calendar: cal).absoluteString,
       "https://calendar.google.com/calendar/u/0/r/day/2026/7/5", "non-padded day URL")
    eq(DeepLinkBuilder.dayURL(for: d(2026, 12, 25, 12, 0), accountIndex: 2, calendar: cal).absoluteString,
       "https://calendar.google.com/calendar/u/2/r/day/2026/12/25", "account index in URL")
}

// MARK: All-day mapping (build DTOs by decoding JSON, as production does)
func decodeEvent(_ json: String) -> GCalEvent {
    try! JSONDecoder().decode(GCalEvent.self, from: Data(json.utf8))
}
do {
    let single = decodeEvent("""
    {"id":"e2","summary":"Holiday","start":{"date":"2026-07-15"},"end":{"date":"2026-07-16"},"status":"confirmed"}
    """)
    if let e = try? CalendarEvent.from(single, calendarId: "c", colorHex: "#abc", calendar: cal) {
        check(e.isAllDay, "all-day detected")
        eq(cal.component(.day, from: e.lastCoveredDay(in: cal)), 15, "exclusive end steps back to the 15th")
        check(e.covers(day: d(2026, 7, 15, 12), calendar: cal), "covers the 15th")
        check(!e.covers(day: d(2026, 7, 16, 12), calendar: cal), "does not cover the 16th")
    } else { check(false, "all-day event should map") }

    let trip = decodeEvent("""
    {"id":"trip","summary":"Trip","start":{"date":"2026-07-15"},"end":{"date":"2026-07-18"},"status":"confirmed"}
    """)
    if let e = try? CalendarEvent.from(trip, calendarId: "c", colorHex: "#000", calendar: cal) {
        for day in 15...17 { check(e.covers(day: d(2026, 7, day, 12), calendar: cal), "trip covers Jul \(day)") }
        check(!e.covers(day: d(2026, 7, 18, 12), calendar: cal), "trip excludes Jul 18")
    } else { check(false, "trip should map") }

    let cancelled = decodeEvent("""
    {"id":"e3","summary":"X","start":{"dateTime":"2026-07-15T17:30:00-07:00"},"end":{"dateTime":"2026-07-15T18:00:00-07:00"},"status":"cancelled"}
    """)
    do {
        let result = try CalendarEvent.from(cancelled, calendarId: "c", colorHex: "#000", calendar: cal)
        check(result == nil, "cancelled event maps to nil")
    } catch { check(false, "cancelled mapping threw: \(error)") }
}

// MARK: Decode fixture
do {
    let json = """
    {"items":[
      {"id":"a","summary":"Lunch","start":{"dateTime":"2026-03-14T12:00:00-07:00"},"end":{"dateTime":"2026-03-14T13:00:00-07:00"},"status":"confirmed"},
      {"id":"b","summary":"Holiday","start":{"date":"2026-03-20"},"end":{"date":"2026-03-21"},"status":"confirmed"}
    ],"nextSyncToken":"TOKEN123"}
    """.data(using: .utf8)!
    if let resp = try? JSONDecoder().decode(GCalEventsResponse.self, from: json) {
        eq(resp.items.count, 2, "decoded 2 events")
        eq(resp.nextSyncToken, "TOKEN123", "decoded sync token")
        let mapped = resp.items.compactMap { try? CalendarEvent.from($0, calendarId: "c", colorHex: "#fff", calendar: cal) }.compactMap { $0 }
        eq(mapped.count, 2, "mapped 2 events")
        eq(mapped.filter { $0.isAllDay }.count, 1, "one all-day among mapped")
    } else { check(false, "fixture should decode") }
}

// MARK: EventCache round-trip + merge
do {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathComponent("events.json")
    let cache = EventCache(fileURL: url)
    let s0 = d(2026, 3, 1, 0, 0)
    let e0 = d(2026, 3, 15, 0, 0)
    let ev1 = ev("1", "One", d(2026, 3, 2, 9), d(2026, 3, 2, 10))
    let data = EventCacheData(generatedAt: s0, windowStart: s0, windowEnd: e0, sources: [], events: [ev1])
    do {
        try cache.write(data)
        eq(cache.read(), data, "cache round-trips")
        check(FileManager.default.fileExists(atPath: url.path), "atomic write created file + dir")
    } catch { check(false, "cache write threw: \(error)") }

    let newEnd = d(2026, 3, 29, 0, 0)
    let fresh1 = ev("1", "Fresh", d(2026, 3, 2, 9), d(2026, 3, 2, 10))
    let ev2 = ev("2", "Two", d(2026, 3, 20, 9), d(2026, 3, 20, 10))
    let merged = data.appending(events: [fresh1, ev2], sources: [], rangeStart: e0, rangeEnd: newEnd, generatedAt: Date())
    eq(merged.windowEnd, newEnd, "append widened window forward")
    eq(Set(merged.events.map { $0.id }), Set(["1", "2"]), "merged event ids")
    eq(merged.events.first { $0.id == "1" }?.title, "Fresh", "incoming event won de-dupe")
}

// MARK: SyncCoordinator canonical range (−2/+6 weeks)
do {
    let now = d(2026, 3, 16, 12)
    let range = SyncCoordinator.canonicalRange(calendar: cal, now: now)
    eq(cal.dateComponents([.day], from: range.start, to: cal.startOfDay(for: now)).day!, 14, "canonical start is 14 days before today")
    eq(cal.dateComponents([.day], from: cal.startOfDay(for: now), to: range.end).day!, 42, "canonical end is 42 days after today")
}

// MARK: Token form-encoding
do {
    eq(TokenRefreshService.formURLEncode(["grant_type": "refresh_token", "refresh_token": "a b/c", "client_id": "id"]),
       "client_id=id&grant_type=refresh_token&refresh_token=a%20b%2Fc", "form-url-encoding sorted + escaped")
}

// MARK: CalendarSyncService (stubbed transport returns canned events per calendar)
final class RoutingTransport: HTTPTransport, @unchecked Sendable {
    // Maps a calendarId substring -> events JSON payload.
    let payloads: [String: String]
    init(_ payloads: [String: String]) { self.payloads = payloads }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!.absoluteString
        let body = payloads.first { url.contains($0.key) }?.value ?? #"{"items":[]}"#
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), resp)
    }
}
func runSyncCheck() async {
    let calA = "personal@example.com".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    _ = calA
    let transport = RoutingTransport([
        "calA/events": #"{"items":[{"id":"e1","summary":"Lunch","start":{"dateTime":"2026-03-14T12:00:00-07:00"},"end":{"dateTime":"2026-03-14T13:00:00-07:00"},"status":"confirmed"}]}"#,
        "calB/events": #"{"items":[{"id":"e2","summary":"Holiday","start":{"date":"2026-03-20"},"end":{"date":"2026-03-21"},"status":"confirmed"}]}"#
    ])
    let api = GoogleCalendarAPIClient(transport: transport)
    let service = CalendarSyncService(api: api, calendar: cal)
    let sources = [
        CalendarSource(id: "calA", accountEmail: "a@example.com", summary: "Personal", colorHex: "#0B8043", isSelected: true),
        CalendarSource(id: "calB", accountEmail: "a@example.com", summary: "Fun", colorHex: "#D50000", isSelected: true),
        CalendarSource(id: "calC", accountEmail: "a@example.com", summary: "Off", colorHex: "#000000", isSelected: false)
    ]
    let result = await service.buildCache(
        sources: sources,
        rangeStart: d(2026, 3, 1),
        rangeEnd: d(2026, 3, 31),
        now: d(2026, 3, 10),
        tokenProvider: { _ in "fake-access-token" }
    )
    eq(result.events.count, 2, "sync merged events from both selected calendars")
    eq(result.sources.count, 2, "unselected calendar excluded from sources")
    eq(result.events.first { $0.id == "e1" }?.colorHex, "#0B8043", "event color denormalized from its source")
    eq(result.events.first { $0.id == "e2" }?.isAllDay, true, "all-day preserved through sync")
}
let syncSem = DispatchSemaphore(value: 0)
Task { await runSyncCheck(); syncSem.signal() }
syncSem.wait()

print("")
if failures == 0 {
    print("✅ All \(checks) CalCore checks passed.")
    exit(0)
} else {
    print("❌ \(failures) of \(checks) checks FAILED.")
    exit(1)
}
