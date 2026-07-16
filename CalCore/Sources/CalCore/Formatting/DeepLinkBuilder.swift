import Foundation

/// Builds the deep link that opens the Google Calendar iOS app to a specific day.
///
/// Format device-confirmed on 2026-07-13: tapping
/// `https://calendar.google.com/calendar/u/0/r/day/YYYY/M/D` prompts to open the
/// Google Calendar app and lands on the correct day. Month/day are NOT zero-padded,
/// matching Google's web day-view URLs.
public enum DeepLinkBuilder {

    /// - Parameters:
    ///   - date: the day to open.
    ///   - accountIndex: Google's on-device account slot (the `/u/N/` segment). Defaults to 0.
    ///     Note: this is the device account index, not necessarily the account that owns the
    ///     calendar shown in the widget (a known multi-account limitation).
    ///   - calendar: injected for testability; determines which day components are used.
    public static func dayURL(for date: Date, accountIndex: Int = 0, calendar: Calendar) -> URL {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let year = comps.year ?? 1970
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let string = "https://calendar.google.com/calendar/u/\(accountIndex)/r/day/\(year)/\(month)/\(day)"
        // Components above are all integers, so this string is always a valid URL.
        return URL(string: string)!
    }
}
