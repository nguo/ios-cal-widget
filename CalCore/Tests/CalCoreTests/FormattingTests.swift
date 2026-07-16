import XCTest
@testable import CalCore

final class FormattingTests: XCTestCase {
    let cal = TestSupport.calendar()

    // MARK: EventTextFormatter

    func testTimePrefixOnTheHourOmitsMinutes() {
        let d = TestSupport.date(2026, 3, 16, 16, 0, calendar: cal)
        XCTAssertEqual(EventTextFormatter.timePrefix(for: d, calendar: cal), "4p")
    }

    func testTimePrefixWithMinutes() {
        let d = TestSupport.date(2026, 3, 16, 17, 30, calendar: cal)
        XCTAssertEqual(EventTextFormatter.timePrefix(for: d, calendar: cal), "5:30p")
    }

    func testTimePrefixMorningWithMinutes() {
        let d = TestSupport.date(2026, 3, 16, 9, 5, calendar: cal)
        XCTAssertEqual(EventTextFormatter.timePrefix(for: d, calendar: cal), "9:05a")
    }

    func testNoonIsTwelveP() {
        let d = TestSupport.date(2026, 3, 16, 12, 0, calendar: cal)
        XCTAssertEqual(EventTextFormatter.timePrefix(for: d, calendar: cal), "12p")
    }

    func testMidnightIsTwelveA() {
        let d = TestSupport.date(2026, 3, 16, 0, 0, calendar: cal)
        XCTAssertEqual(EventTextFormatter.timePrefix(for: d, calendar: cal), "12a")
    }

    func testLineForTimedEvent() {
        let start = TestSupport.date(2026, 3, 16, 16, 0, calendar: cal)
        let e = TestSupport.event(id: "1", title: "Party", start: start, end: start)
        XCTAssertEqual(EventTextFormatter.line(for: e, calendar: cal), "4p Party")
    }

    func testAllDayHasNoPrefix() {
        let start = TestSupport.date(2026, 3, 20, 0, 0, calendar: cal)
        let e = TestSupport.event(id: "1", title: "Holiday", start: start, end: start, isAllDay: true)
        XCTAssertNil(EventTextFormatter.timePrefix(for: e, calendar: cal))
        XCTAssertEqual(EventTextFormatter.line(for: e, calendar: cal), "Holiday")
    }

    // MARK: DayCellContent (3 events + smart 4th line)

    private func timed(_ id: String, hour: Int) -> CalendarEvent {
        let s = TestSupport.date(2026, 3, 16, hour, 0, calendar: cal)
        return TestSupport.event(id: id, title: "E\(id)", start: s, end: s)
    }

    func testThreeEventsShowAll() {
        let content = DayCellContent(events: [timed("1", hour: 9), timed("2", hour: 10), timed("3", hour: 11)], calendar: cal)
        XCTAssertEqual(content.rows.count, 3)
        if case .moreCount = content.rows.last { XCTFail("should not have a more-count row") }
    }

    func testExactlyFourEventsShowAllFour() {
        let events = (1...4).map { timed("\($0)", hour: 8 + $0) }
        let content = DayCellContent(events: events, calendar: cal)
        XCTAssertEqual(content.rows.count, 4)
        for row in content.rows {
            guard case .event = row else { return XCTFail("all rows should be events, got \(row)") }
        }
    }

    func testFiveEventsShowThreePlusMore() {
        let events = (1...5).map { timed("\($0)", hour: 8 + $0) }
        let content = DayCellContent(events: events, calendar: cal)
        XCTAssertEqual(content.rows.count, 4)
        XCTAssertEqual(content.rows.last, .moreCount(2), "5 events -> 3 shown + '+2 more'")
    }

    func testAllDaySortsBeforeTimed() {
        let allDayStart = TestSupport.date(2026, 3, 16, 0, 0, calendar: cal)
        let allDay = TestSupport.event(id: "hol", title: "Holiday", start: allDayStart, end: allDayStart, isAllDay: true)
        let content = DayCellContent(events: [timed("1", hour: 9), allDay], calendar: cal)
        guard case let .event(first) = content.rows.first else { return XCTFail() }
        XCTAssertTrue(first.isAllDay, "all-day event should sort first")
    }

    // MARK: DeepLinkBuilder

    func testDayURLIsNonPaddedConfirmedFormat() {
        let d = TestSupport.date(2026, 7, 5, 12, 0, calendar: cal)
        let url = DeepLinkBuilder.dayURL(for: d, calendar: cal)
        XCTAssertEqual(url.absoluteString, "https://calendar.google.com/calendar/u/0/r/day/2026/7/5")
    }

    func testDayURLRespectsAccountIndex() {
        let d = TestSupport.date(2026, 12, 25, 12, 0, calendar: cal)
        let url = DeepLinkBuilder.dayURL(for: d, accountIndex: 2, calendar: cal)
        XCTAssertEqual(url.absoluteString, "https://calendar.google.com/calendar/u/2/r/day/2026/12/25")
    }

    func testScheduleURLUsesNonPaddedAgendaRoute() {
        let d = TestSupport.date(2026, 7, 5, 12, 0, calendar: cal)
        let url = DeepLinkBuilder.scheduleURL(for: d, calendar: cal)
        XCTAssertEqual(url.absoluteString, "https://calendar.google.com/calendar/u/0/r/agenda/2026/7/5")
    }

    func testEventURLIsTheCanonicalHtmlLink() {
        // The event deep link is Google's own htmlLink, used verbatim (device-confirmed to open the
        // Google Calendar app to the exact event).
        let html = "https://www.google.com/calendar/event?eid=YWJjMTIzIG5pbmE"
        XCTAssertEqual(DeepLinkBuilder.eventURL(htmlLink: html)?.absoluteString, html)
    }
}
