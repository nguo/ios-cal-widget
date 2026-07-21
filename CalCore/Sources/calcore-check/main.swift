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

    // clock without meridiem (start side of a range)
    eq(EventTextFormatter.clock(for: d(2026, 3, 16, 9, 30), calendar: cal, meridiem: false), "9:30", "9:30 -> 9:30 (no meridiem)")
    eq(EventTextFormatter.clock(for: d(2026, 3, 16, 16, 0), calendar: cal, meridiem: false), "4", "16:00 -> 4 (no meridiem)")
    // timeRange: only the end carries am/pm
    eq(EventTextFormatter.timeRange(for: ev("2", "M", d(2026, 3, 16, 9, 30), d(2026, 3, 16, 10, 0)), calendar: cal), "9:30-10a", "9:30-10a")
    eq(EventTextFormatter.timeRange(for: ev("3", "M", d(2026, 3, 16, 9, 0), d(2026, 3, 16, 22, 30)), calendar: cal), "9-10:30p", "9-10:30p")
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
    eq(DeepLinkBuilder.eventURL(htmlLink: "https://www.google.com/calendar/event?eid=YWJjMTIz")?.absoluteString ?? "nil",
       "https://www.google.com/calendar/event?eid=YWJjMTIz", "event htmlLink passthrough")
    eq(DeepLinkBuilder.scheduleURL(for: d(2026, 7, 5, 12, 0), calendar: cal).absoluteString,
       "https://calendar.google.com/calendar/u/0/r/agenda/2026/7/5", "schedule (agenda) view URL")
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

// MARK: SyncCoordinator canonical range (today .. +2 weeks)
do {
    let now = d(2026, 3, 16, 12)
    let range = SyncCoordinator.canonicalRange(calendar: cal, now: now)
    eq(cal.dateComponents([.day], from: range.start, to: cal.startOfDay(for: now)).day!, 0, "canonical start is today")
    eq(cal.dateComponents([.day], from: cal.startOfDay(for: now), to: range.end).day!,
       AppConfig.agendaHorizonDays, "canonical end is agendaHorizonDays after today")
}

// MARK: canonicalRange widened to cover the (week-aligned) widget window
do {
    // Mid-week "today": the grid window is week-aligned, so both the offset −1 window and the
    // offset 0 window start before the canonical start (today), so plain canonical fails to
    // cover them (the "tap to refresh" bug); the widened range must cover them.
    let now = d(2026, 3, 18, 12) // Wednesday
    let plain = SyncCoordinator.canonicalRange(calendar: cal, now: now)
    let plainCache = EventCacheData(generatedAt: now, windowStart: plain.start, windowEnd: plain.end, sources: [], events: [])

    func checkCovers(_ offset: Int, _ label: String) {
        let window = DateWindow(referenceDate: now, pageOffset: offset, weekCount: 2, calendar: cal)
        check(!plainCache.covers(start: window.startDate, end: window.endExclusive), "plain canonical does NOT cover the \(label) window (the bug)")
        let widened = SyncCoordinator.canonicalRange(coveringOffset: offset, weekCount: 2, calendar: cal, now: now)
        let widenedCache = EventCacheData(generatedAt: now, windowStart: widened.start, windowEnd: widened.end, sources: [], events: [])
        check(widenedCache.covers(start: window.startDate, end: window.endExclusive), "widened range covers the \(label) window")
    }

    checkCovers(0, "offset 0")   // week-aligned start (Sunday) is before today
    checkCovers(-1, "offset −1") // previous window
}

// MARK: One canonical range must satisfy BOTH widgets
do {
    // The grid and the agenda want different windows: the grid is week-aligned (most-recent
    // Sunday … +14d), the agenda is today … +agendaHorizonDays. Every sync writes exactly one
    // range now, so that range has to cover both or one widget renders short.
    for hour in [0, 12, 23] {
        for dayOfMonth in 15 ... 21 { // a full week of "today"s, Sunday through Saturday
            let now = d(2026, 3, dayOfMonth, hour)
            let range = SyncCoordinator.canonicalRange(coveringOffset: 0, weekCount: 2, calendar: cal, now: now)
            let cache = EventCacheData(generatedAt: now, windowStart: range.start, windowEnd: range.end,
                                       sources: [], events: [])

            let grid = DateWindow(referenceDate: now, pageOffset: 0, weekCount: 2, calendar: cal)
            check(cache.covers(start: grid.startDate, end: grid.endExclusive),
                  "canonical range covers the week-aligned grid window (Mar \(dayOfMonth), \(hour)h)")

            let todayStart = cal.startOfDay(for: now)
            let horizonEnd = cal.date(byAdding: .day, value: AppConfig.agendaHorizonDays, to: todayStart)!
            check(cache.covers(start: todayStart, end: horizonEnd),
                  "canonical range covers the agenda horizon (Mar \(dayOfMonth), \(hour)h)")
        }
    }
}

// MARK: Refreshing while paged forward refetches the visible window
do {
    // The refresh button syncs at the *current* offset, so a widget paged past the canonical
    // window still gets fresh events for the page on screen.
    let now = d(2026, 3, 18, 12)
    for offset in [1, 2, 5] {
        let range = SyncCoordinator.canonicalRange(coveringOffset: offset, weekCount: 2, calendar: cal, now: now)
        let cache = EventCacheData(generatedAt: now, windowStart: range.start, windowEnd: range.end,
                                   sources: [], events: [])
        let window = DateWindow(referenceDate: now, pageOffset: offset, weekCount: 2, calendar: cal)
        check(cache.covers(start: window.startDate, end: window.endExclusive),
              "refresh at offset +\(offset) covers the visible window")
    }
}

// MARK: Canonical end is derived from the agenda horizon, not a matching constant
do {
    let now = d(2026, 3, 18, 12)
    let range = SyncCoordinator.canonicalRange(calendar: cal, now: now)
    eq(cal.dateComponents([.day], from: cal.startOfDay(for: now), to: range.end).day!,
       AppConfig.agendaHorizonDays, "canonical end tracks agendaHorizonDays")
}

// MARK: Multi-day spans survive a canonical (replace-only) sync
do {
    // Sync replaces the cache with exactly today … +14d, so a trip that began before today meets
    // a window that starts today. Google returns it (timeMin bounds an event's *end*), and the
    // ordering must clip it to the horizon instead of dropping it for starting out of range.
    let today = d(2026, 3, 5)
    let trip = ev("trip", "Trip", d(2026, 3, 1), d(2026, 3, 8), allDay: true) // Mar 1–7 inclusive
    let cache = EventCacheData(generatedAt: today, windowStart: today, windowEnd: d(2026, 3, 19),
                               sources: [], events: [trip])
    let days = AgendaPagination.orderedEvents(reference: today, calendar: cal, cache: cache)
        .map { cal.component(.day, from: $0.day) }
    eq(days, [5, 6, 7], "span starting before the window shows from today through its last day")
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
    // The cache is a superset: buildCache fetches every source passed in. calC has no
    // events route, so it contributes nothing but is still retained as an available source.
    let sources = [
        CalendarSource(id: "calA", accountEmail: "a@example.com", summary: "Personal", colorHex: "#0B8043"),
        CalendarSource(id: "calB", accountEmail: "a@example.com", summary: "Fun", colorHex: "#D50000"),
        CalendarSource(id: "calC", accountEmail: "a@example.com", summary: "Empty", colorHex: "#000000")
    ]
    guard let result = await service.buildCache(
        sources: sources,
        rangeStart: d(2026, 3, 1),
        rangeEnd: d(2026, 3, 31),
        now: d(2026, 3, 10),
        tokenProvider: { _ in "fake-access-token" }
    ) else {
        check(false, "buildCache returned nil despite reachable calendars")
        return
    }
    eq(result.events.count, 2, "sync merged events from the calendars that had events")
    eq(result.sources.count, 3, "every passed calendar retained as an available source")
    eq(result.events.first { $0.id == "e1" }?.colorHex, "#0B8043", "event color denormalized from its source")
    eq(result.events.first { $0.id == "e2" }?.isAllDay, true, "all-day preserved through sync")

    // A total failure must NOT yield an empty-but-valid cache: the caller would write it and
    // stamp it as freshly synced, silently blanking the widget after a transient network drop.
    final class DeadTransport: HTTPTransport, @unchecked Sendable {
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let resp = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data("boom".utf8), resp)
        }
    }
    let dead = CalendarSyncService(api: GoogleCalendarAPIClient(transport: DeadTransport()), calendar: cal)
    let failed = await dead.buildCache(
        sources: sources, rangeStart: d(2026, 3, 1), rangeEnd: d(2026, 3, 31),
        now: d(2026, 3, 10), tokenProvider: { _ in "fake-access-token" }
    )
    check(failed == nil, "every-calendar-failed sync returns nil instead of an empty cache")
}
let syncSem = DispatchSemaphore(value: 0)
Task { await runSyncCheck(); syncSem.signal() }
syncSem.wait()

// MARK: WeekLayout — spanning all-day segments + lane packing
do {
    let week = (0..<7).map { d(2026, 3, 1 + $0) } // Mar 1..7 = columns 0..6
    func allDay(_ id: String, _ title: String, _ startDay: Int, _ endExclusiveDay: Int, color: String = "#4285F4") -> CalendarEvent {
        ev(id, title, d(2026, 3, startDay), d(2026, 3, endExclusiveDay), allDay: true)
    }
    func byDay(_ events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
        var m: [Date: [CalendarEvent]] = [:]
        for day in week { m[day] = events.filter { $0.covers(day: day, calendar: cal) } }
        return m
    }

    // Single 3-day span Mar 2–4 → cols 1..3, one lane, no continuation.
    let trip = allDay("trip", "Trip", 2, 5)
    let l1 = WeekLayout(days: week, eventsByDay: byDay([trip]), calendar: cal, maxRowsPerCell: 4)
    eq(l1.allDaySegments.count, 1, "one all-day segment")
    eq(l1.allDaySegments.first?.startColumn, 1, "segment startColumn = Mar 2")
    eq(l1.allDaySegments.first?.endColumn, 3, "segment endColumn = Mar 4")
    eq(l1.laneCount, 1, "one lane")
    eq(l1.allDaySegments.first?.continuesLeft, false, "does not continue left")
    eq(l1.allDaySegments.first?.continuesRight, false, "does not continue right")

    // Two overlapping all-day events → 2 lanes.
    let conf = allDay("conf", "Conf", 3, 6) // Mar 3–5, overlaps Trip
    let l2 = WeekLayout(days: week, eventsByDay: byDay([trip, conf]), calendar: cal, maxRowsPerCell: 4)
    eq(l2.laneCount, 2, "overlapping all-day events -> 2 lanes")
    eq(Set(l2.allDaySegments.map { $0.lane }), Set([0, 1]), "segments on distinct lanes")

    // Two NON-overlapping all-day events share one lane (packing).
    let solo = allDay("solo", "Solo", 6, 7) // Mar 6, after Trip ends
    let l3 = WeekLayout(days: week, eventsByDay: byDay([trip, solo]), calendar: cal, maxRowsPerCell: 4)
    eq(l3.laneCount, 1, "non-overlapping all-day events pack into one lane")

    // Cross-week: event starting before this week → clipped + continuesLeft.
    let long = ev("long", "Long", d(2026, 2, 26), d(2026, 3, 3), allDay: true) // Feb 26–Mar 2
    let l4 = WeekLayout(days: week, eventsByDay: byDay([long]), calendar: cal, maxRowsPerCell: 4)
    eq(l4.allDaySegments.first?.startColumn, 0, "cross-week clipped to col 0")
    eq(l4.allDaySegments.first?.endColumn, 1, "cross-week last covered = Mar 2 (col 1)")
    eq(l4.allDaySegments.first?.continuesLeft, true, "continues left (started prior week)")

    // Timed budget reduced by lane count.
    let s = d(2026, 3, 3, 9)
    let timedEvents = (1...4).map { ev("t\($0)", "T\($0)", d(2026, 3, 3, 8 + $0), d(2026, 3, 3, 9 + $0)) }
    let l5 = WeekLayout(days: week, eventsByDay: byDay([trip] + timedEvents), calendar: cal, maxRowsPerCell: 4)
    _ = s
    // col 2 (Mar 3) has the 4 timed events; with 1 all-day lane, timed budget = 3 → 2 shown + "+2 more".
    eq(l5.timedByColumn[2]?.rows.count, 3, "timed budget reduced to 3 rows on a lane-occupied column")
    if case .moreCount = l5.timedByColumn[2]?.rows.last {} else { check(false, "expected a +N more row when timed overflow") }

    // Per-column reservation: a column with NO all-day covering it keeps its full top row/budget.
    eq(l5.lanesByColumn[0], 0, "uncovered column reserves 0 lanes")
    eq(l5.lanesByColumn[2], 1, "column under the trip reserves 1 lane")
    let farTimed = (1...4).map { ev("f\($0)", "F\($0)", d(2026, 3, 6, 8 + $0), d(2026, 3, 6, 9 + $0)) }
    let l6 = WeekLayout(days: week, eventsByDay: byDay([trip] + farTimed), calendar: cal, maxRowsPerCell: 4)
    eq(l6.timedByColumn[5]?.rows.count, 4, "uncovered column keeps full 4-row budget (no blank first line)")
}

// MARK: Agenda pagination — the page math the widget extension used to hide
do {
    let metrics = AgendaMetrics(dayHeaderHeight: 18, allDayRowHeight: 16, timedRowHeight: 30, pageBudget: 100)
    let fit = AgendaPageSizing.heightFit(metrics)
    func at(_ day: Int, _ hour: Int) -> Date { d(2026, 3, day, hour) }
    func timed(_ id: String, _ day: Int, _ hour: Int) -> CalendarEvent {
        ev(id, id, at(day, hour), at(day, hour + 1))
    }
    func cacheOf(_ events: [CalendarEvent]) -> EventCacheData {
        EventCacheData(generatedAt: d(2026, 3, 1), windowStart: d(2026, 3, 1),
                       windowEnd: d(2026, 3, 28), sources: [], events: events)
    }
    func ordered(_ events: [CalendarEvent], from: Date = d(2026, 3, 1)) -> [AgendaSlot] {
        AgendaPagination.orderedEvents(reference: from, calendar: cal, cache: cacheOf(events))
    }

    let allDay = ev("banner", "Banner", d(2026, 3, 1), d(2026, 3, 2), allDay: true)
    eq(ordered([timed("t", 1, 9), allDay]).map(\.event.id), ["banner", "t"],
       "all-day sorts before timed within a day")

    let ended = ordered([timed("over", 1, 9), timed("later", 1, 17)], from: at(1, 12))
    eq(ended.map(\.event.id), ["later"], "already-ended timed events drop off")

    // 18 (header) + 30 + 30 = 78 fits a 100pt budget; a third row would be 108.
    eq(fit.eventsThatFit(ordered([timed("a", 1, 9), timed("b", 1, 11), timed("c", 1, 13)]), from: 0), 2,
       "height-fit charges the day header once and stops at the budget")

    let tiny = AgendaPageSizing.heightFit(
        AgendaMetrics(dayHeaderHeight: 18, allDayRowHeight: 16, timedRowHeight: 30, pageBudget: 5))
    eq(tiny.eventsThatFit(ordered([timed("a", 1, 9)]), from: 0), 1,
       "a lone oversized event still fills a page (never a zero-length page)")

    // Paging must be reversible and must reach every event.
    let many = ordered((1 ... 10).map { timed("e\($0)", $0, 9) })
    let bounds = AgendaPagination.boundaries(many, sizing: fit)
    eq(bounds.first, 0, "boundaries start at 0")
    check(bounds == bounds.sorted() && Set(bounds).count == bounds.count, "boundaries ascend, no repeats")
    var reachable: [String] = []
    for start in bounds {
        reachable += AgendaPagination.groups(from: many, offset: start, sizing: fit).flatMap { $0.events.map(\.id) }
    }
    eq(reachable, many.map(\.event.id), "paging reaches every event exactly once")
    let fwd = AgendaPagination.steppedOffset(from: 0, direction: 1, bounds: bounds)
    eq(AgendaPagination.steppedOffset(from: fwd, direction: -1, bounds: bounds), 0, "forward then back returns home")
    eq(AgendaPagination.steppedOffset(from: 0, direction: -1, bounds: bounds), 0, "paging back from page 1 clamps")
    eq(AgendaPagination.pageStart(for: 5, in: [0, 3, 7]), 3, "a drifted offset snaps back to its boundary")

    // Continuation flag: a page opening mid-day renders "(cont)".
    let sameDay = ordered([timed("a", 1, 9), timed("b", 1, 11), timed("c", 1, 13)])
    eq(AgendaPagination.groups(from: sameDay, offset: 1, sizing: .fixedCount(2)).first?.isContinuation, true,
       "page opening mid-day is a continuation")
    eq(AgendaPagination.groups(from: sameDay, offset: 0, sizing: .fixedCount(2)).first?.isContinuation, false,
       "first page is never a continuation")
}

// MARK: Calendar-id URL encoding (holiday/contacts calendars carry a "#")
do {
    let id = "en.usa#holiday@group.v.calendar.google.com"
    eq(GoogleCalendarAPIClient.eventsPath(calendarId: id),
       "/calendars/en.usa%23holiday@group.v.calendar.google.com/events",
       "calendar-id '#' escaped once in the path")
    let url = try! GoogleCalendarAPIClient.makeURL(
        encodedPath: GoogleCalendarAPIClient.eventsPath(calendarId: id),
        query: [URLQueryItem(name: "singleEvents", value: "true")]
    )
    check(!url.absoluteString.contains("%2523"), "calendar id is not double-encoded")
    eq(url.absoluteString,
       "https://www.googleapis.com/calendar/v3/calendars/en.usa%23holiday@group.v.calendar.google.com/events?singleEvents=true",
       "full events URL for a '#'-bearing calendar id")
    eq(GoogleCalendarAPIClient.eventsPath(calendarId: "a/b"), "/calendars/a%2Fb/events",
       "'/' in a calendar id can't split the path")
}

// MARK: Deep-link host trust
do {
    func trusted(_ s: String) -> Bool { DeepLinkBuilder.isTrustedGoogleHost(URL(string: s)!) }
    check(trusted("https://calendar.google.com/calendar/u/0/r/day/2026/7/19"), "subdomain accepted")
    check(trusted("https://google.com/calendar"), "apex domain accepted")
    check(!trusted("https://evilgoogle.com/calendar"), "lookalike host rejected")
    check(!trusted("https://google.com.attacker.net"), "suffixed host rejected")
    check(!trusted("http://calendar.google.com"), "non-https rejected")
}

print("")
if failures == 0 {
    print("✅ All \(checks) CalCore checks passed.")
    exit(0)
} else {
    print("❌ \(failures) of \(checks) checks FAILED.")
    exit(1)
}
