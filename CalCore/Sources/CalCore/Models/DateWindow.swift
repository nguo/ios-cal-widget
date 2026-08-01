import Foundation

/// A contiguous run of `weekCount * 7` days, aligned to week boundaries (Sunday-first
/// to match the widget's "S M T W T F S" header), shifted by `pageOffset` whole windows
/// from the window containing the reference date.
///
/// Generic over `weekCount` so a future 1-week or 3-week widget reuses this unchanged.
public struct DateWindow: Equatable, Sendable {
    public let weekCount: Int
    public let pageOffset: Int
    /// First day of the window (a Sunday, at start-of-day).
    public let startDate: Date
    /// All `weekCount * 7` days, ascending, each at start-of-day.
    public let days: [Date]

    /// Number of days in the window.
    public var dayCount: Int { weekCount * 7 }

    /// Exclusive end: start-of-day of the day *after* the last day in the window.
    /// Convenient for range checks (`startDate ..< endExclusive`).
    ///
    /// Stored, not computed, because getting it right needs the calendar — and this used to add a
    /// flat 86,400 seconds instead. A window's last day is a Saturday, and several zones shift the
    /// clock at midnight *entering Sunday* (America/Santiago, America/Nuuk, Asia/Beirut,
    /// Asia/Gaza, Pacific/Easter), which makes that Saturday 23 or 25 hours long. On the 25-hour
    /// one the flat day landed at 23:00 Saturday — an hour inside the window it was supposed to
    /// bound — so the fetch's `timeMax` cut an hour early and events in the window's final hour
    /// went missing, and consecutive windows no longer abutted.
    public let endExclusive: Date

    /// Builds the window for the given reference date and offset.
    /// - Parameters:
    ///   - referenceDate: usually "now".
    ///   - pageOffset: 0 = window containing the reference date; +1 = next window; -1 = previous.
    ///   - weekCount: number of weeks (2 for the two-week widget).
    ///   - calendar: injected for testability; caller should set the desired timezone.
    ///     `firstWeekday` is forced to Sunday internally.
    public init(referenceDate: Date, pageOffset: Int, weekCount: Int, calendar: Calendar) {
        var cal = calendar
        cal.firstWeekday = 1 // Sunday

        let anchorWeekStart = Self.startOfWeek(for: referenceDate, calendar: cal)
        let shiftDays = pageOffset * weekCount * 7
        let start = cal.date(byAdding: .day, value: shiftDays, to: anchorWeekStart) ?? anchorWeekStart

        var days: [Date] = []
        days.reserveCapacity(weekCount * 7)
        for i in 0 ..< (weekCount * 7) {
            if let d = cal.date(byAdding: .day, value: i, to: start) {
                days.append(cal.startOfDay(for: d))
            }
        }

        self.weekCount = weekCount
        self.pageOffset = pageOffset
        self.startDate = cal.startOfDay(for: start)
        self.days = days
        // Same day-stepping the `days` loop uses, so the end lands on a real midnight and the
        // next window's first day is exactly this instant.
        let lastDay = days.last ?? cal.startOfDay(for: start)
        self.endExclusive = cal.date(byAdding: .day, value: 1, to: lastDay)
            .map { cal.startOfDay(for: $0) } ?? lastDay
    }

    /// The Sunday (start-of-day) beginning the week that contains `date`.
    static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
            return interval.start
        }
        return calendar.startOfDay(for: date)
    }

    /// Uppercased month name of the window's first day (e.g. "MARCH"), matching the mockup.
    /// When the window spans two months we still label by the first day's month.
    public func monthLabel(calendar: Calendar, locale: Locale = .current) -> String {
        let formatter = DateFormatterCache.shared.formatter(format: "MMMM", calendar: calendar, locale: locale)
        return formatter.string(from: startDate).uppercased(with: locale)
    }
}
