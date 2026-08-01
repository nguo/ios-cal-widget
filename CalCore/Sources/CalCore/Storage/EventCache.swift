import Foundation

/// The on-disk cache the app writes and the widget reads. One flat, pre-merged file
/// so the widget's timeline provider does minimal work: load, filter to the window, render.
public struct EventCacheData: Codable, Equatable, Sendable {
    public var generatedAt: Date
    /// The rolling range actually cached (inclusive start, exclusive-ish end).
    public var windowStart: Date
    public var windowEnd: Date
    public var sources: [CalendarSource]
    public var events: [CalendarEvent]

    public init(
        generatedAt: Date,
        windowStart: Date,
        windowEnd: Date,
        sources: [CalendarSource],
        events: [CalendarEvent]
    ) {
        self.generatedAt = generatedAt
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.sources = sources
        self.events = events
    }

    /// Whether the given [start, end) range is fully covered by the cached window.
    public func covers(start: Date, end: Date) -> Bool {
        start >= windowStart && end <= windowEnd
    }

    /// The events one widget instance should consider: restricted to its calendar selection
    /// (nil ⇒ every calendar in the cache) and, unless `showDeclined`, with declined events
    /// dropped.
    ///
    /// Single definition of "visible" on purpose. This pair of predicates used to be written
    /// out separately in the grid builder, the agenda ordering, and the agenda's reload
    /// scheduling — and the third one drifting from the other two would schedule widget reloads
    /// for events the widget doesn't actually render.
    public func visibleEvents(calendarIds: Set<String>?, showDeclined: Bool) -> [CalendarEvent] {
        events.filter { event in
            if let calendarIds, !calendarIds.contains(event.calendarId) { return false }
            return showDeclined || !event.isDeclined
        }
    }

    /// PAGINATION path: widen the cache to include a freshly fetched range, merging in
    /// its events/sources without discarding what's already cached. De-dupes by
    /// `CalendarEvent.cacheKey` (incoming wins). Use when the user pages into a range not yet
    /// cached.
    ///
    /// The key is calendar + id, not id alone: the same meeting reachable through two calendars
    /// returns once per calendar under the same id, and those are two rows the widget draws in
    /// two colors. Keying on id merged them into one and handed the survivor whichever calendar
    /// arrived last, so paging into an uncached window silently dropped a copy and could recolor
    /// the other. The canonical path never had this — it replaces wholesale and de-dupes nothing.
    public func appending(
        events newEvents: [CalendarEvent],
        sources newSources: [CalendarSource],
        rangeStart: Date,
        rangeEnd: Date,
        generatedAt now: Date
    ) -> EventCacheData {
        var eventsByKey: [CalendarEvent.CacheKey: CalendarEvent] = [:]
        for e in events { eventsByKey[e.cacheKey] = e }
        for e in newEvents { eventsByKey[e.cacheKey] = e } // incoming wins

        var sourcesById: [String: CalendarSource] = [:]
        for s in sources { sourcesById[s.id] = s }
        for s in newSources { sourcesById[s.id] = s }

        // Sorts are cosmetic — they keep output deterministic for tests. Events tie-break on the
        // cache key because start date alone isn't a total order: the duplicates this merge now
        // preserves are the *same* meeting in two calendars, so they share a start exactly, and
        // ordering them by dictionary iteration would vary run to run.
        return EventCacheData(
            generatedAt: now,
            windowStart: min(windowStart, rangeStart),
            windowEnd: max(windowEnd, rangeEnd),
            sources: sourcesById.values.sorted { $0.id < $1.id },
            events: eventsByKey.values.sorted {
                ($0.startDate, $0.calendarId, $0.id) < ($1.startDate, $1.calendarId, $1.id)
            }
        )
    }
}

/// Reads and writes `EventCacheData` to a file in the shared App Group container.
/// Writes are atomic (write-to-temp + rename) so an interrupted sync never leaves a
/// partial/corrupted cache — the previous good file simply survives.
public struct EventCache {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Standard location inside an App Group container.
    public init?(appGroupIdentifier: String, filename: String = "events.json") {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }
        self.fileURL = container.appendingPathComponent(filename)
    }

    public func read() -> EventCacheData? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.calDecoder.decode(EventCacheData.self, from: data)
    }

    /// Atomically writes the full cache. Because the caller builds the complete
    /// `EventCacheData` in memory first and only calls this on success, a killed or
    /// failed sync leaves the prior file untouched — freshness may lag, but the cache
    /// is never partially written.
    public func write(_ cache: EventCacheData) throws {
        let data = try JSONEncoder.calEncoder.encode(cache)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var calEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var calDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
