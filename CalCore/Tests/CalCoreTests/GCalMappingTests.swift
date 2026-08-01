import XCTest
@testable import CalCore

final class GCalMappingTests: XCTestCase {
    let cal = TestSupport.calendar()

    func testAllDayDetection() {
        let allDay = GCalEventDateTime(date: "2026-07-15", dateTime: nil, timeZone: nil)
        let timed = GCalEventDateTime(date: nil, dateTime: "2026-07-15T16:00:00-07:00", timeZone: nil)
        XCTAssertTrue(CalendarEvent.isAllDay(allDay))
        XCTAssertFalse(CalendarEvent.isAllDay(timed))
    }

    func testMapTimedEvent() throws {
        let g = GCalEvent(
            id: "e1", summary: "Meeting",
            start: GCalEventDateTime(date: nil, dateTime: "2026-07-15T17:30:00-07:00", timeZone: nil),
            end: GCalEventDateTime(date: nil, dateTime: "2026-07-15T18:00:00-07:00", timeZone: nil),
            status: "confirmed", htmlLink: nil, attendees: nil
        )
        let e = try XCTUnwrap(try CalendarEvent.from(g, calendarId: "cal1", colorHex: "#123456", calendar: cal))
        XCTAssertFalse(e.isAllDay)
        XCTAssertFalse(e.isDeclined)
        XCTAssertEqual(EventTextFormatter.timePrefix(for: e, calendar: cal), "5:30p")
        XCTAssertEqual(e.colorHex, "#123456")
        XCTAssertEqual(e.title, "Meeting")
    }

    func testMapAllDayEventExclusiveEnd() throws {
        // Single all-day event on Jul 15: Google sends end.date = Jul 16 (exclusive).
        let g = GCalEvent(
            id: "e2", summary: "Holiday",
            start: GCalEventDateTime(date: "2026-07-15", dateTime: nil, timeZone: nil),
            end: GCalEventDateTime(date: "2026-07-16", dateTime: nil, timeZone: nil),
            status: "confirmed", htmlLink: nil, attendees: nil
        )
        let e = try XCTUnwrap(try CalendarEvent.from(g, calendarId: "cal1", colorHex: "#abcdef", calendar: cal))
        XCTAssertTrue(e.isAllDay)
        let lastDay = e.lastCoveredDay(in: cal)
        XCTAssertEqual(cal.component(.day, from: lastDay), 15, "exclusive end.date must step back to the 15th")
        XCTAssertTrue(e.covers(day: TestSupport.date(2026, 7, 15, 12, calendar: cal), calendar: cal))
        XCTAssertFalse(e.covers(day: TestSupport.date(2026, 7, 16, 12, calendar: cal), calendar: cal))
    }

    func testMultiDayAllDayCoversAllDays() throws {
        // 3-day trip Jul 15-17 -> end.date Jul 18 exclusive.
        let g = GCalEvent(
            id: "trip", summary: "Trip",
            start: GCalEventDateTime(date: "2026-07-15", dateTime: nil, timeZone: nil),
            end: GCalEventDateTime(date: "2026-07-18", dateTime: nil, timeZone: nil),
            status: "confirmed", htmlLink: nil, attendees: nil
        )
        let e = try XCTUnwrap(try CalendarEvent.from(g, calendarId: "cal1", colorHex: "#000", calendar: cal))
        for day in 15...17 {
            XCTAssertTrue(e.covers(day: TestSupport.date(2026, 7, day, 12, calendar: cal), calendar: cal), "should cover Jul \(day)")
        }
        XCTAssertFalse(e.covers(day: TestSupport.date(2026, 7, 18, 12, calendar: cal), calendar: cal))
    }

    func testCancelledEventReturnsNil() throws {
        let g = GCalEvent(
            id: "e3", summary: "Cancelled",
            start: GCalEventDateTime(date: nil, dateTime: "2026-07-15T17:30:00-07:00", timeZone: nil),
            end: GCalEventDateTime(date: nil, dateTime: "2026-07-15T18:00:00-07:00", timeZone: nil),
            status: "cancelled", htmlLink: nil, attendees: nil
        )
        XCTAssertNil(try CalendarEvent.from(g, calendarId: "cal1", colorHex: "#000", calendar: cal))
    }

    /// A calendar shared as free/busy returns every event with no `summary`. "(No title)" would
    /// read as "nobody named it" when the truth is "you may not see the name".
    func testFreeBusyOnlyEventsAreTitledBusy() throws {
        let g = GCalEvent(
            id: "fb1", summary: nil,
            start: GCalEventDateTime(date: nil, dateTime: "2026-07-15T17:30:00-07:00", timeZone: nil),
            end: GCalEventDateTime(date: nil, dateTime: "2026-07-15T18:00:00-07:00", timeZone: nil),
            status: "confirmed", htmlLink: nil, attendees: nil
        )
        let busy = try XCTUnwrap(try CalendarEvent.from(g, calendarId: "shared", colorHex: "#000",
                                                        calendar: cal, isFreeBusyOnly: true))
        XCTAssertEqual(busy.title, "Busy")

        // Same payload on a calendar you can actually read is a genuinely untitled event.
        let untitled = try XCTUnwrap(try CalendarEvent.from(g, calendarId: "mine", colorHex: "#000",
                                                             calendar: cal, isFreeBusyOnly: false))
        XCTAssertEqual(untitled.title, "(No title)")
    }

    /// A free/busy calendar that *does* send a title (Google varies by sharing setting) must keep
    /// it — the fallback is a fallback, not an override.
    func testFreeBusyOnlyKeepsARealTitleWhenPresent() throws {
        let g = GCalEvent(
            id: "fb2", summary: "Standup",
            start: GCalEventDateTime(date: nil, dateTime: "2026-07-15T17:30:00-07:00", timeZone: nil),
            end: GCalEventDateTime(date: nil, dateTime: "2026-07-15T18:00:00-07:00", timeZone: nil),
            status: "confirmed", htmlLink: nil, attendees: nil
        )
        let e = try XCTUnwrap(try CalendarEvent.from(g, calendarId: "shared", colorHex: "#000",
                                                      calendar: cal, isFreeBusyOnly: true))
        XCTAssertEqual(e.title, "Standup")
    }

    /// `accessRole` drives the flag, and only that one value means free/busy.
    func testAccessRoleMapsToFreeBusyFlag() throws {
        func entry(_ role: String?) -> GCalCalendarListEntry {
            GCalCalendarListEntry(id: "c", summary: "C", backgroundColor: nil, primary: nil, accessRole: role)
        }
        XCTAssertTrue(entry("freeBusyReader").isFreeBusyOnly)
        XCTAssertFalse(entry("reader").isFreeBusyOnly)
        XCTAssertFalse(entry("owner").isFreeBusyOnly)
        XCTAssertFalse(entry(nil).isFreeBusyOnly, "a response without the field must not read as free/busy")
    }

    /// Caches written before `isFreeBusyOnly` existed must still decode.
    func testCalendarSourceDecodesWithoutTheFreeBusyField() throws {
        // Double-hash delimiter: the color's "#" would otherwise close a #"..."# raw string.
        let json = ##"{"id":"c1","accountEmail":"a@b.com","summary":"Work","colorHex":"#fff"}"##
        let source = try JSONDecoder().decode(CalendarSource.self, from: Data(json.utf8))
        XCTAssertFalse(source.isFreeBusyOnly)
        XCTAssertEqual(source.summary, "Work")
    }

    func testDeclinedBySelfAttendee() throws {
        let start = GCalEventDateTime(date: nil, dateTime: "2026-07-15T17:30:00-07:00", timeZone: nil)
        let end = GCalEventDateTime(date: nil, dateTime: "2026-07-15T18:00:00-07:00", timeZone: nil)
        // Declined: our own row (self == true) is "declined"; another guest's status is ignored.
        let declined = GCalEvent(
            id: "d1", summary: "Skip", start: start, end: end, status: "confirmed", htmlLink: nil,
            attendees: [
                GCalAttendee(selfAttendee: false, responseStatus: "accepted"),
                GCalAttendee(selfAttendee: true, responseStatus: "declined")
            ]
        )
        let accepted = GCalEvent(
            id: "d2", summary: "Attend", start: start, end: end, status: "confirmed", htmlLink: nil,
            attendees: [GCalAttendee(selfAttendee: true, responseStatus: "accepted")]
        )
        let e1 = try XCTUnwrap(try CalendarEvent.from(declined, calendarId: "cal1", colorHex: "#000", calendar: cal))
        let e2 = try XCTUnwrap(try CalendarEvent.from(accepted, calendarId: "cal1", colorHex: "#000", calendar: cal))
        XCTAssertTrue(e1.isDeclined)
        XCTAssertFalse(e2.isDeclined)
    }

    func testDecodeEventsListFixture() throws {
        let json = """
        {
          "items": [
            {
              "id": "a",
              "summary": "Lunch",
              "start": { "dateTime": "2026-03-14T12:00:00-07:00" },
              "end":   { "dateTime": "2026-03-14T13:00:00-07:00" },
              "status": "confirmed"
            },
            {
              "id": "b",
              "summary": "Holiday",
              "start": { "date": "2026-03-20" },
              "end":   { "date": "2026-03-21" },
              "status": "confirmed"
            }
          ],
          "nextSyncToken": "TOKEN123"
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(GCalEventsResponse.self, from: json)
        XCTAssertEqual(resp.items.count, 2)
        XCTAssertEqual(resp.nextSyncToken, "TOKEN123")

        let mapped = try resp.items.compactMap {
            try CalendarEvent.from($0, calendarId: "cal1", colorHex: "#fff", calendar: cal)
        }
        XCTAssertEqual(mapped.count, 2)
        XCTAssertEqual(mapped.filter { $0.isAllDay }.count, 1)
        XCTAssertEqual(mapped.first { $0.id == "a" }?.isAllDay, false)
        XCTAssertEqual(mapped.first { $0.id == "b" }?.isAllDay, true)
    }

    func testParseDateTimeWithFractionalSeconds() {
        let d = CalendarEvent.parseDateTime("2026-07-15T16:00:00.000-07:00")
        XCTAssertNotNil(d, "should parse RFC3339 with fractional seconds")
    }
}
