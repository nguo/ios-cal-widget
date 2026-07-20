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

    /// PAGINATION path: widen the cache to include a freshly fetched range, merging in
    /// its events/sources without discarding what's already cached. De-dupes by id
    /// (incoming wins). Use when the user pages into a range not yet cached.
    public func appending(
        events newEvents: [CalendarEvent],
        sources newSources: [CalendarSource],
        rangeStart: Date,
        rangeEnd: Date,
        generatedAt now: Date
    ) -> EventCacheData {
        var eventsById: [String: CalendarEvent] = [:]
        for e in events { eventsById[e.id] = e }
        for e in newEvents { eventsById[e.id] = e } // incoming wins

        var sourcesById: [String: CalendarSource] = [:]
        for s in sources { sourcesById[s.id] = s }
        for s in newSources { sourcesById[s.id] = s }

        // Sorts are cosmetic — they keep output deterministic for tests.
        return EventCacheData(
            generatedAt: now,
            windowStart: min(windowStart, rangeStart),
            windowEnd: max(windowEnd, rangeEnd),
            sources: sourcesById.values.sorted { $0.id < $1.id },
            events: eventsById.values.sorted { $0.startDate < $1.startDate }
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
