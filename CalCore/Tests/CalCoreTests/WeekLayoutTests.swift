import XCTest
@testable import CalCore

final class WeekLayoutTests: XCTestCase {
    let cal = TestSupport.calendar()

    private func week() -> [Date] { (0..<7).map { TestSupport.date(2026, 3, 1 + $0, 0, calendar: cal) } } // Mar 1..7

    private func allDay(_ id: String, _ title: String, _ startDay: Int, _ endExclusiveDay: Int) -> CalendarEvent {
        TestSupport.event(id: id, title: title,
                          start: TestSupport.date(2026, 3, startDay, 0, calendar: cal),
                          end: TestSupport.date(2026, 3, endExclusiveDay, 0, calendar: cal),
                          isAllDay: true)
    }

    private func byDay(_ events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
        var m: [Date: [CalendarEvent]] = [:]
        for day in week() { m[day] = events.filter { $0.covers(day: day, calendar: cal) } }
        return m
    }

    func testSingleMultiDaySpan() {
        let trip = allDay("trip", "Trip", 2, 5) // Mar 2–4 → cols 1..3
        let layout = WeekLayout(days: week(), eventsByDay: byDay([trip]), calendar: cal, maxRowsPerCell: 4)
        XCTAssertEqual(layout.allDaySegments.count, 1)
        let seg = layout.allDaySegments[0]
        XCTAssertEqual(seg.startColumn, 1)
        XCTAssertEqual(seg.endColumn, 3)
        XCTAssertEqual(seg.columnSpan, 3)
        XCTAssertEqual(layout.laneCount, 1)
        XCTAssertFalse(seg.continuesLeft)
        XCTAssertFalse(seg.continuesRight)
    }

    func testOverlappingAllDayGetsTwoLanes() {
        let trip = allDay("trip", "Trip", 2, 5)
        let conf = allDay("conf", "Conf", 3, 6) // overlaps
        let layout = WeekLayout(days: week(), eventsByDay: byDay([trip, conf]), calendar: cal, maxRowsPerCell: 4)
        XCTAssertEqual(layout.laneCount, 2)
        XCTAssertEqual(Set(layout.allDaySegments.map { $0.lane }), [0, 1])
    }

    func testNonOverlappingAllDayShareLane() {
        let trip = allDay("trip", "Trip", 2, 5) // cols 1..3
        let solo = allDay("solo", "Solo", 6, 7) // col 5
        let layout = WeekLayout(days: week(), eventsByDay: byDay([trip, solo]), calendar: cal, maxRowsPerCell: 4)
        XCTAssertEqual(layout.laneCount, 1)
    }

    func testCrossWeekContinuesLeft() {
        // Feb 26 .. Mar 2 (starts before this week Mar 1–7).
        let e = TestSupport.event(id: "long", title: "Long",
                                  start: TestSupport.date(2026, 2, 26, 0, calendar: cal),
                                  end: TestSupport.date(2026, 3, 3, 0, calendar: cal),
                                  isAllDay: true)
        let layout = WeekLayout(days: week(), eventsByDay: byDay([e]), calendar: cal, maxRowsPerCell: 4)
        XCTAssertEqual(layout.allDaySegments.first?.startColumn, 0)
        XCTAssertEqual(layout.allDaySegments.first?.endColumn, 1) // last covered = Mar 2
        XCTAssertEqual(layout.allDaySegments.first?.continuesLeft, true)
    }

    func testTimedBudgetReducedByLanes() {
        let trip = allDay("trip", "Trip", 2, 5)
        let timed = (1...4).map {
            TestSupport.event(id: "t\($0)", title: "T\($0)",
                              start: TestSupport.date(2026, 3, 3, 8 + $0, calendar: cal),
                              end: TestSupport.date(2026, 3, 3, 9 + $0, calendar: cal))
        }
        let layout = WeekLayout(days: week(), eventsByDay: byDay([trip] + timed), calendar: cal, maxRowsPerCell: 4)
        // col 2 = Mar 3; 1 all-day lane → timed budget 3 → 2 shown + "+2 more".
        XCTAssertEqual(layout.timedByColumn[2]?.rows.count, 3)
        if case .moreCount = layout.timedByColumn[2]?.rows.last {} else {
            XCTFail("expected a +N more row")
        }
    }

    func testUncoveredColumnKeepsFullBudget() {
        // A day with no all-day event covering it must NOT reserve lane space (no blank first row).
        let trip = allDay("trip", "Trip", 2, 5) // covers cols 1..3
        let far = (1...4).map {
            TestSupport.event(id: "f\($0)", title: "F\($0)",
                              start: TestSupport.date(2026, 3, 6, 8 + $0, calendar: cal),
                              end: TestSupport.date(2026, 3, 6, 9 + $0, calendar: cal))
        }
        let layout = WeekLayout(days: week(), eventsByDay: byDay([trip] + far), calendar: cal, maxRowsPerCell: 4)
        XCTAssertEqual(layout.lanesByColumn[0], 0)   // uncovered
        XCTAssertEqual(layout.lanesByColumn[2], 1)   // under the trip
        XCTAssertEqual(layout.timedByColumn[5]?.rows.count, 4) // Mar 6 keeps full budget
    }
}
