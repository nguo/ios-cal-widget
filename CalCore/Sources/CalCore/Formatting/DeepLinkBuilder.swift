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
        renderURL(view: "day", for: date, accountIndex: accountIndex, calendar: calendar)
    }

    /// Opens Google Calendar's Schedule view (the `agenda` render route — Google renamed the UI
    /// label from "Agenda" to "Schedule" but kept `agenda` in the URL) scrolled to `date`. The
    /// two-week widget uses this so tapping a day lands on a scrolling list of events from that day.
    /// Device-confirmed 2026-07-16.
    public static func scheduleURL(for date: Date, accountIndex: Int = 0, calendar: Calendar) -> URL {
        renderURL(view: "agenda", for: date, accountIndex: accountIndex, calendar: calendar)
    }

    /// Builds a Google Calendar app-render URL `/r/<view>/YYYY/M/D` (month/day non-zero-padded,
    /// matching Google's day-view URLs).
    private static func renderURL(view: String, for date: Date, accountIndex: Int, calendar: Calendar) -> URL {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let year = comps.year ?? 1970
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let string = "https://calendar.google.com/calendar/u/\(accountIndex)/r/\(view)/\(year)/\(month)/\(day)"
        // Components above are all integers, so this string is always a valid URL.
        return URL(string: string)!
    }

    /// Opens the Google Calendar app to a single event: Google's own canonical event link, i.e. the
    /// event's `htmlLink` from the API (form `https://www.google.com/calendar/event?eid=<eid>`).
    ///
    /// Device-confirmed 2026-07-16: this raw link opens the app to the exact event. Two approaches
    /// that did NOT work and are deliberately avoided: hand-encoding our own `eid` (padding-stripped,
    /// so Google couldn't decode it), and rehosting Google's `eid` under the `/r/eventedit/` render
    /// route (opened the app but fell back to the base view). The canonical link is the one to use.
    ///
    /// Returns nil only for an unusable string; callers should fall back to `dayURL`.
    ///
    /// - Parameter htmlLink: the event's `htmlLink` (`CalendarEvent.htmlLink`).
    public static func eventURL(htmlLink: String) -> URL? {
        URL(string: htmlLink)
    }

    /// Whether a URL is safe to hand to `openURL` as a Google Calendar deep link.
    ///
    /// Requires https plus an exact host match or a *true* subdomain. A plain
    /// `host.hasSuffix("google.com")` — what this replaced — also accepts `evilgoogle.com`
    /// and `notgoogle.com`, because suffix matching ignores label boundaries.
    /// Single gate for both deep-link paths: the app's `onOpenURL` router, and the forwarder
    /// that drains whatever a widget intent stashed in the App Group.
    public static func isTrustedGoogleHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "google.com" || host.hasSuffix(".google.com")
    }
}
