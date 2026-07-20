import Foundation

/// Shared, pre-configured date formatters.
///
/// `DateFormatter` initialization is genuinely expensive — on the order of milliseconds — and
/// these sat in two hot paths: the widget's render loop built one per agenda row per render,
/// and the sync's parse loop built three per event, so a 500-event sync churned through roughly
/// fifteen hundred of them.
///
/// Formatters are safe to *use* concurrently as long as nothing mutates them after
/// configuration, so each is configured once and only ever read afterwards. Treat every
/// formatter handed out here as immutable — mutating one corrupts it for every other caller.
public final class DateFormatterCache: @unchecked Sendable {
    public static let shared = DateFormatterCache()

    /// Cached per timezone/locale/calendar as well as format: a cache keyed on format alone
    /// would keep serving a formatter built for the old zone after the user travels or the
    /// device rolls over a DST boundary.
    private struct Key: Hashable {
        let format: String
        let timeZone: String
        let localeID: String
        let calendarID: Calendar.Identifier
    }

    private let lock = NSLock()
    private var storage: [Key: DateFormatter] = [:]

    private init() {}

    /// A formatter for `format`, in `calendar`'s timezone. Do not mutate the result.
    public func formatter(format: String, calendar: Calendar, locale: Locale = .current) -> DateFormatter {
        let key = Key(
            format: format,
            timeZone: calendar.timeZone.identifier,
            localeID: locale.identifier,
            calendarID: calendar.identifier
        )
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key] { return cached }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = format
        storage[key] = formatter
        return formatter
    }
}

/// RFC3339 parsers for Google's `dateTime` values. No calendar or locale dependency — the
/// format carries its own offset — so these are plain immutable singletons.
enum ISO8601Parsers {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Formats an instant for a `timeMin`/`timeMax` query parameter.
    static let query = ISO8601DateFormatter()
}
