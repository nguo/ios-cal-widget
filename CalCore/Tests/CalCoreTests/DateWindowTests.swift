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
