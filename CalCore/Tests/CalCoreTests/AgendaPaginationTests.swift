import XCTest
@testable import CalCore

/// The agenda page math, finally testable off-device. Previously it lived in the widget
/// extension, so none of this could be exercised without rendering a widget by hand.
final class AgendaPaginationTests: XCTestCase {
    private let cal = TestSupport.calendar()

    /// Roughly the small widget's real geometry: an 18pt day header, 16pt all-day rows,
    /// 30pt timed rows, in a 100pt budget.
    private let metrics = AgendaMetrics(
        dayHeaderHeight: 18, allDayRowHeight: 16, timedRowHeight: 30, pageBudget: 100
    )
    private var heightFit: AgendaPageSizing { .heightFit(metrics) }

    private func day(_ d: Int) -> Date { TestSupport.date(2026, 3, d, 0, calendar: cal) }

    private func timed(_ id: String, _ d: Int, _ hour: Int, minutes: Int = 60) -> CalendarEvent {
        let start = TestSupport.date(2026, 3, d, hour, calendar: cal)
        return TestSupport.event(id: id, title: id, start: start,
                                 end: start.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    private func allDay(_ id: String, from: Int, toExclusive: Int) -> CalendarEvent {
        TestSupport.event(id: id, title: id, start: day(from), end: day(toExclusive), isAllDay: true)
    }

    private func cache(_ events: [CalendarEvent]) -> EventCacheData {
        EventCacheData(generatedAt: day(1), windowStart: day(1), windowEnd: day(28),
                       sources: [], events: events)
    }

    private func slots(_ events: [CalendarEvent], from reference: Date? = nil) -> [AgendaSlot] {
        AgendaPagination.orderedEvents(
            reference: reference ?? day(1), calendar: cal, cache: cache(events)
        )
    }

    // MARK: - Ordering

    /// A span that began before the cache window's start still has to show on the days it covers
    /// from today forward. Sync writes exactly one canonical range and replaces it wholesale, so
    /// this is the case where a trip started last week meets a cache that starts today: Google's
    /// timeMin bounds an event's *end*, so the span comes back in the fetch, and the ordering has
    /// to clip it to the horizon rather than drop it for starting out of range.
    func testMultiDaySpanStartingBeforeTheReferenceStillAppears() {
        let trip = allDay("trip", from: 1, toExclusive: 8) // Mar 1–7 inclusive
        let ordered = slots([trip], from: day(5))
        XCTAssertEqual(ordered.map { cal.component(.day, from: $0.day) }, [5, 6, 7],
                       "clipped to today forward, through its last covered day")
    }

    func testAllDayEventsSortBeforeTimedWithinADay() {
        let ordered = slots([timed("t", 1, 9), allDay("a", from: 1, toExclusive: 2)])
        XCTAssertEqual(ordered.map(\.event.id), ["a", "t"])
    }

    func testTimedEventsSortAscendingByStart() {
        let ordered = slots([timed("late", 1, 17), timed("early", 1, 9), timed("mid", 1, 12)])
        XCTAssertEqual(ordered.map(\.event.id), ["early", "mid", "late"])
    }

    /// A multi-day all-day event appears once under each day it covers, so the agenda repeats
    /// it as the reader paginates forward.
    func testMultiDayEventAppearsUnderEachCoveredDay() {
        let ordered = slots([allDay("trip", from: 2, toExclusive: 5)])
        XCTAssertEqual(ordered.map(\.day), [day(2), day(3), day(4)])
    }

    func testEmptyDaysAreSkipped() {
        let ordered = slots([timed("a", 1, 9), timed("b", 5, 9)])
        XCTAssertEqual(ordered.map(\.day), [day(1), day(5)])
    }

    /// A timed event already over shouldn't linger on the widget; all-day events and future
    /// days are unaffected.
    func testEndedTimedEventsAreExcluded() {
        let noon = TestSupport.date(2026, 3, 1, 12, calendar: cal)
        let ordered = slots(
            [timed("over", 1, 9), timed("later", 1, 17), allDay("banner", from: 1, toExclusive: 2)],
            from: noon
        )
        XCTAssertEqual(ordered.map(\.event.id), ["banner", "later"])
    }

    func testHorizonBoundsTheList() {
        let ordered = AgendaPagination.orderedEvents(
            reference: day(1), calendar: cal,
            cache: cache([timed("in", 2, 9), timed("out", 20, 9)]),
            horizonDays: 5
        )
        XCTAssertEqual(ordered.map(\.event.id), ["in"])
    }

    func testCalendarSelectionAndDeclinedFilterApply() {
        let mine = TestSupport.event(id: "mine", title: "Mine", start: day(1).addingTimeInterval(3600),
                                     end: day(1).addingTimeInterval(7200), calendarId: "keep")
        let theirs = TestSupport.event(id: "theirs", title: "Theirs", start: day(1).addingTimeInterval(3600),
                                       end: day(1).addingTimeInterval(7200), calendarId: "drop")
        let ordered = AgendaPagination.orderedEvents(
            reference: day(1), calendar: cal, cache: cache([mine, theirs]), refs: [TestSupport.ref("keep")]
        )
        XCTAssertEqual(ordered.map(\.event.id), ["mine"])
    }

    // MARK: - Page sizing

    /// Costs must include the per-day header: 18 + 30 + 30 = 78 fits 100, adding a third timed
    /// row (108) does not.
    func testHeightFitCountsDayHeaderOnce() {
        let ordered = slots([timed("a", 1, 9), timed("b", 1, 11), timed("c", 1, 13)])
        XCTAssertEqual(heightFit.eventsThatFit(ordered, from: 0), 2)
    }

    /// A new day re-charges the header, so a page spanning days holds fewer events.
    func testHeightFitChargesHeaderPerDay() {
        // day1: 18+30 = 48; day2: +18+30 = 96 fits; a third would be 18+30 more.
        let ordered = slots([timed("a", 1, 9), timed("b", 2, 9), timed("c", 3, 9)])
        XCTAssertEqual(heightFit.eventsThatFit(ordered, from: 0), 2)
    }

    /// All-day rows are shorter than timed ones, so more of them fit.
    func testAllDayRowsAreCheaperThanTimed() {
        let allDayOnly = slots([allDay("a", from: 1, toExclusive: 2), allDay("b", from: 1, toExclusive: 2),
                                allDay("c", from: 1, toExclusive: 2), allDay("d", from: 1, toExclusive: 2)])
        let timedOnly = slots([timed("a", 1, 9), timed("b", 1, 11), timed("c", 1, 13), timed("d", 1, 15)])
        XCTAssertGreaterThan(
            heightFit.eventsThatFit(allDayOnly, from: 0),
            timedOnly.count > 0 ? heightFit.eventsThatFit(timedOnly, from: 0) : 0
        )
    }

    /// A lone event taller than the whole budget must still render (clipped) rather than
    /// yielding a zero-length page, which would make paging spin forever.
    func testOversizedSingleEventStillFits() {
        let tiny = AgendaPageSizing.heightFit(
            AgendaMetrics(dayHeaderHeight: 18, allDayRowHeight: 16, timedRowHeight: 30, pageBudget: 5)
        )
        XCTAssertEqual(tiny.eventsThatFit(slots([timed("a", 1, 9)]), from: 0), 1)
    }

    func testFixedCountClampsToRemaining() {
        let ordered = slots([timed("a", 1, 9), timed("b", 1, 11), timed("c", 1, 13)])
        XCTAssertEqual(AgendaPageSizing.fixedCount(4).eventsThatFit(ordered, from: 0), 3)
        XCTAssertEqual(AgendaPageSizing.fixedCount(2).eventsThatFit(ordered, from: 0), 2)
        XCTAssertEqual(AgendaPageSizing.fixedCount(2).eventsThatFit(ordered, from: 2), 1)
    }

    /// The two variants page differently on purpose — that's why they keep separate offsets.
    func testHeightFitAndFixedCountDivergeOnTheSameList() {
        let ordered = slots([timed("a", 1, 9), timed("b", 1, 11), timed("c", 1, 13), timed("d", 1, 15)])
        XCTAssertNotEqual(
            AgendaPagination.boundaries(ordered, sizing: heightFit),
            AgendaPagination.boundaries(ordered, sizing: .fixedCount(4))
        )
    }

    // MARK: - Boundaries

    func testBoundariesAreEmptyListSafe() {
        XCTAssertEqual(AgendaPagination.boundaries([], sizing: heightFit), [0])
    }

    func testBoundariesStartAtZeroAndAscend() {
        let ordered = slots((1 ... 8).map { timed("e\($0)", $0, 9) })
        let bounds = AgendaPagination.boundaries(ordered, sizing: heightFit)
        XCTAssertEqual(bounds.first, 0)
        XCTAssertEqual(bounds, bounds.sorted())
        XCTAssertEqual(Set(bounds).count, bounds.count, "boundaries must not repeat")
    }

    /// The property that makes paging usable: stepping forward then back must return you to
    /// the page you started on, for every page.
    func testForwardThenBackReturnsToTheSamePage() {
        let ordered = slots((1 ... 10).map { timed("e\($0)", $0, 9) })
        let bounds = AgendaPagination.boundaries(ordered, sizing: heightFit)
        for start in bounds {
            let forward = AgendaPagination.steppedOffset(from: start, direction: 1, bounds: bounds)
            let back = AgendaPagination.steppedOffset(from: forward, direction: -1, bounds: bounds)
            if forward != start { XCTAssertEqual(back, start) } // unless clamped at the last page
        }
    }

    func testSteppingClampsAtBothEnds() {
        let ordered = slots((1 ... 6).map { timed("e\($0)", $0, 9) })
        let bounds = AgendaPagination.boundaries(ordered, sizing: heightFit)
        XCTAssertEqual(AgendaPagination.steppedOffset(from: 0, direction: -1, bounds: bounds), 0)
        let last = bounds.last!
        XCTAssertEqual(AgendaPagination.steppedOffset(from: last, direction: 1, bounds: bounds), last)
    }

    /// A stored offset can land between boundaries after a re-sync changes the event list.
    func testPageStartSnapsBackToNearestBoundary() {
        let bounds = [0, 3, 7, 11]
        XCTAssertEqual(AgendaPagination.pageStart(for: 5, in: bounds), 3)
        XCTAssertEqual(AgendaPagination.pageStart(for: 3, in: bounds), 3)
        XCTAssertEqual(AgendaPagination.pageStart(for: 0, in: bounds), 0)
        XCTAssertEqual(AgendaPagination.pageStart(for: 99, in: bounds), 11)
    }

    /// Paging must reach every event — no gaps, no skipped pages.
    func testBoundariesCoverEveryEventExactlyOnce() {
        let ordered = slots((1 ... 12).map { timed("e\($0)", $0, 9) })
        let bounds = AgendaPagination.boundaries(ordered, sizing: heightFit)
        var seen: [String] = []
        for start in bounds {
            seen += AgendaPagination.groups(from: ordered, offset: start, sizing: heightFit)
                .flatMap { $0.events.map(\.id) }
        }
        XCTAssertEqual(seen, ordered.map(\.event.id))
    }

    // MARK: - Grouping

    func testGroupsCollapseConsecutiveEventsOfTheSameDay() {
        let ordered = slots([timed("a", 1, 9), timed("b", 1, 11), timed("c", 2, 9)])
        let groups = AgendaPagination.groups(from: ordered, offset: 0, sizing: .fixedCount(3))
        XCTAssertEqual(groups.map(\.day), [day(1), day(2)])
        XCTAssertEqual(groups.first?.events.map(\.id), ["a", "b"])
    }

    /// A page opening partway through a day is flagged so the header renders as "(cont)".
    func testPageOpeningMidDayIsMarkedContinuation() {
        let ordered = slots([timed("a", 1, 9), timed("b", 1, 11), timed("c", 1, 13)])
        let groups = AgendaPagination.groups(from: ordered, offset: 1, sizing: .fixedCount(2))
        XCTAssertEqual(groups.first?.isContinuation, true)
    }

    func testPageStartingOnANewDayIsNotContinuation() {
        let ordered = slots([timed("a", 1, 9), timed("b", 2, 9)])
        let groups = AgendaPagination.groups(from: ordered, offset: 1, sizing: .fixedCount(2))
        XCTAssertEqual(groups.first?.isContinuation, false)
    }

    func testFirstPageIsNeverContinuation() {
        let ordered = slots([timed("a", 1, 9), timed("b", 1, 11)])
        let groups = AgendaPagination.groups(from: ordered, offset: 0, sizing: .fixedCount(1))
        XCTAssertEqual(groups.first?.isContinuation, false)
    }

    func testGroupsPastTheEndAreEmpty() {
        XCTAssertTrue(AgendaPagination.groups(from: slots([timed("a", 1, 9)]), offset: 5,
                                              sizing: heightFit).isEmpty)
    }

    // MARK: - Reload scheduling

    /// Reload points must track the *visible* set: an event on a deselected calendar would
    /// otherwise wake the widget to render exactly the same thing.
    func testUpcomingEndTimesRespectCalendarSelection() {
        let noon = TestSupport.date(2026, 3, 1, 12, calendar: cal)
        let keep = TestSupport.event(id: "k", title: "K", start: noon,
                                     end: noon.addingTimeInterval(3600), calendarId: "keep")
        let drop = TestSupport.event(id: "d", title: "D", start: noon,
                                     end: noon.addingTimeInterval(1800), calendarId: "drop")
        let ends = AgendaPagination.upcomingEndTimes(
            after: noon, before: day(2), cache: cache([keep, drop]), refs: [TestSupport.ref("keep")]
        )
        XCTAssertEqual(ends, [keep.endDate])
    }

    func testUpcomingEndTimesExcludeAllDayAndAreSortedUnique() {
        let noon = TestSupport.date(2026, 3, 1, 12, calendar: cal)
        let late = timed("late", 1, 17)
        let early = timed("early", 1, 14)
        let dupe = TestSupport.event(id: "dupe", title: "Dupe", start: early.startDate,
                                     end: early.endDate, calendarId: "other")
        let ends = AgendaPagination.upcomingEndTimes(
            after: noon, before: day(2),
            cache: cache([late, early, dupe, allDay("banner", from: 1, toExclusive: 2)])
        )
        XCTAssertEqual(ends, [early.endDate, late.endDate])
    }

    /// Unbounded entry counts are a real memory cost inside the extension.
    func testUpcomingEndTimesAreCapped() {
        let midnight = day(1)
        let many = (0 ..< 40).map { i -> CalendarEvent in
            let start = midnight.addingTimeInterval(TimeInterval(i * 600 + 600))
            return TestSupport.event(id: "e\(i)", title: "E", start: start,
                                     end: start.addingTimeInterval(60))
        }
        let ends = AgendaPagination.upcomingEndTimes(
            after: midnight, before: day(2), cache: cache(many), limit: 12
        )
        XCTAssertEqual(ends.count, 12)
        XCTAssertEqual(ends, ends.sorted(), "the earliest reload points are the ones kept")
    }
}
