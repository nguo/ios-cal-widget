import Foundation

/// Every calendar the signed-in accounts can see — what the widget's picker offers, and the
/// lookup that turns a widget's selected `CalendarRef`s back into fetchable sources.
///
/// Separate from `EventCacheData` because the two now hold different sets. The catalog is
/// *everything available* and costs one `calendarList` request per account; the events cache holds
/// only the calendars some placed widget actually selected. Keeping them in one file would mean
/// either fetching events for every calendar of every account — 45 requests for three accounts,
/// well past what an App Intent's time budget or Google's rate limiter tolerates — or having no
/// way to offer a calendar in the picker before its events exist.
public struct CalendarCatalog: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var sources: [CalendarSource]

    public init(generatedAt: Date, sources: [CalendarSource]) {
        self.generatedAt = generatedAt
        self.sources = sources
    }

    public var accountEmails: [String] {
        var seen: Set<String> = []
        return sources.map(\.accountEmail).filter { seen.insert($0).inserted }
    }

    public func sources(for accountEmail: String) -> [CalendarSource] {
        sources.filter { $0.accountEmail == accountEmail }
    }

    /// The sources named by `refs`, in catalog order. Refs with no match are dropped — a calendar
    /// can be unshared or an account removed while a widget still names it.
    public func resolve(_ refs: Set<CalendarRef>) -> [CalendarSource] {
        sources.filter { refs.contains($0.ref) }
    }

    /// Replaces `accountEmail`'s entries with `fresh`, leaving every other account untouched.
    /// Accounts are listed one at a time and any of them can fail; dropping a failed account's
    /// calendars would empty that half of the picker and make live widget selections
    /// unresolvable, which reads to the user as "my widget forgot its calendars".
    public func replacing(accountEmail: String, with fresh: [CalendarSource], generatedAt now: Date) -> CalendarCatalog {
        CalendarCatalog(
            generatedAt: now,
            sources: sources.filter { $0.accountEmail != accountEmail } + fresh
        )
    }

    /// Drops an account entirely — the removal path, as opposed to a failed listing.
    public func removing(accountEmail: String, generatedAt now: Date) -> CalendarCatalog {
        CalendarCatalog(generatedAt: now, sources: sources.filter { $0.accountEmail != accountEmail })
    }
}

/// Reads and writes `CalendarCatalog` to a file in the shared App Group container. Atomic writes,
/// same as `EventCache` — an interrupted listing leaves the previous catalog intact.
public struct CatalogStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init?(appGroupIdentifier: String, filename: String = "calendars.json") {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }
        self.fileURL = container.appendingPathComponent(filename)
    }

    public func read() -> CalendarCatalog? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.calDecoder.decode(CalendarCatalog.self, from: data)
    }

    public func write(_ catalog: CalendarCatalog) throws {
        let data = try JSONEncoder.calEncoder.encode(catalog)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
