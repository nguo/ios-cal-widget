import XCTest
@testable import CalCore

final class DateWindowTests: XCTestCase {
    let cal = TestSupport.calendar()

    func testWindowHasCorrectDayCount() {
        let ref = TestSupport.date(2026, 3, 16, 12, calendar: cal)
        let w = DateWindow(referenceDate: ref, pageOffset: 0, weekCount: 2, calendar: cal)
        XCTAssertEqual(w.days.count, 14)
        XCTAssertEqual(w.dayCount, 14)
    }

    func testWindowStartsOnSunday() {
        let ref = TestSupport.date(2026, 3, 16, 12, calendar: cal) // a Monday
        let w = DateWindow(referenceDate: ref, pageOffset: 0, weekCount: 2, calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: w.startDate), 1, "startDate must be a Sunday")
    }

    func testCurrentWindowContainsReferenceDay() {
        let ref = TestSupport.date(2026, 3, 16, 12, calendar: cal)
        let w = DateWindow(referenceDate: ref, pageOffset: 0, weekCount: 2, calendar: cal)
        let refDay = cal.startOfDay(for: ref)
        XCTAssertTrue(w.days.contains(refDay), "offset 0 window should include today")
    }

    func testDaysAreConsecutiveStartOfDay() {
        let ref = TestSupport.date(2026, 3, 16, 12, calendar: cal)
        let w = DateWindow(referenceDate: ref, pageOffset: 0, weekCount: 2, calendar: cal)
        for i in 1 ..< w.days.count {
            let expected = cal.date(byAdding: .day, value: 1, to: w.days[i - 1])!
            XCTAssertEqual(w.days[i], expected)
            XCTAssertEqual(w.days[i], cal.startOfDay(for: w.days[i]))
        }
    }

    func testForwardOffsetShiftsByFourteenDays() {
        let ref = TestSupport.date(2026, 3, 16, 12, calendar: cal)
        let current = DateWindow(referenceDate: ref, pageOffset: 0, weekCount: 2, calendar: cal)
        let next = DateWindow(referenceDate: ref, pageOffset: 1, weekCount: 2, calendar: cal)
        let diff = cal.dateComponents([.day], from: current.startDate, to: next.startDate).day
        XCTAssertEqual(diff, 14)
        XCTAssertEqual(next.days.first, current.endExclusive)
    }

    /// A window's last day is a Saturday, and several zones move the clock at midnight entering
    /// Sunday — so that Saturday runs 23 or 25 hours. Santiago's April fall-back makes it 25, and
    /// a flat 86,400s end landed at 23:00 Saturday: an hour inside the window it bounds, which
    /// cut the fetch's `timeMax` short and left a gap between consecutive windows.
    func testEndExclusiveLandsOnMidnightAcrossADSTShift() {
        let santiago = TestSupport.calendar(tz: "America/Santiago")
        // Sun 2026-03-22 … Sat 2026-04-04, the Saturday Santiago falls back.
        let ref = TestSupport.date(2026, 3, 25, 12, calendar: santiago)
        let window = DateWindow(referenceDate: ref, pageOffset: 0, weekCount: 2, calendar: santiago)

        XCTAssertEqual(window.days.last, TestSupport.date(2026, 4, 4, 0, calendar: santiago))
        XCTAssertEqual(window.endExclusive, santiago.startOfDay(for: TestSupport.date(2026, 4, 5, 12, calendar: santiago)),
                       "end must be the next real midnight, not last day + 24h")

        let next = DateWindow(referenceDate: ref, pageOffset: 1, weekCount: 2, calendar: santiago)
        XCTAssertEqual(next.days.first, window.endExclusive, "windows must abut with no gap")
    }

    /// The same property, in a zone with no transition in range — the fix must not perturb the
    /// ordinary case.
    func testEndExclusiveAbutsWithoutADSTShift() {
        let ref = TestSupport.date(2026, 6, 10, 12, calendar: cal)
        let window = DateWindow(referenceDate: ref, pageOffset: 0, weekCount: 2, calendar: cal)
        let next = DateWindow(referenceDate: ref, pageOffset: 1, weekCount: 2, calendar: cal)
        XCTAssertEqual(next.days.first, window.endExclusive)
        XCTAssertEqual(window.endExclusive.timeIntervalSince(window.days.last!), 86_400)
    }

    func testBackwardOffsetShiftsBackFourteenDays() {
        let ref = TestSupport.date(2026, 3, 16, 12, calendar: cal)
        let current = DateWindow(referenceDate: ref, pageOffset: 0, weekCount: 2, calendar: cal)
        let prev = DateWindow(referenceDate: ref, pageOffset: -1, weekCount: 2, calendar: cal)
        let diff = cal.dateComponents([.day], from: prev.startDate, to: current.startDate).day
        XCTAssertEqual(diff, 14)
    }

    func testMonthLabelUsesFirstDayMonth() {
        let ref = TestSupport.date(2026, 3, 16, 12, calendar: cal)
        let w = DateWindow(referenceDate: ref, pageOffset: 0, weekCount: 2, calendar: cal)
        // First day is in March 2026.
        XCTAssertEqual(cal.component(.month, from: w.startDate), 3)
        XCTAssertEqual(w.monthLabel(calendar: cal, locale: Locale(identifier: "en_US")), "MARCH")
    }

    func testOneWeekVariantReusesSameLogic() {
        let ref = TestSupport.date(2026, 3, 16, 12, calendar: cal)
        let w = DateWindow(referenceDate: ref, pageOffset: 1, weekCount: 1, calendar: cal)
        XCTAssertEqual(w.days.count, 7)
        // A 1-week window paged once should shift by 7 days.
        let current = DateWindow(referenceDate: ref, pageOffset: 0, weekCount: 1, calendar: cal)
        let diff = cal.dateComponents([.day], from: current.startDate, to: w.startDate).day
        XCTAssertEqual(diff, 7)
    }
}
