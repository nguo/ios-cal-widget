import Foundation

/// The on-disk cache the app writes and the widget reads. One flat, pre-merged file
/// so the widget's timeline provider does minimal work: load, filter to the window, render.
///
/// This holds only the calendars some placed widget actually selected — the *demanded* subset.
/// The full list of calendars available across every signed-in account lives in `CalendarCatalog`
/// and is what the widget's picker offers.
public struct EventCacheData: Codable, Equatable, Sendable {
    public var generatedAt: Date
    /// The rolling range actually cached (inclusive start, exclusive-ish end).
    public var windowStart: Date
    public var windowEnd: Date
    /// The calendars whose events are in this file — i.e. what was demanded at the last sync.
    /// Not a catalog of what exists; that's `CalendarCatalog`.
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

    /// The refs whose events this file holds.
    public var coveredRefs: Set<CalendarRef> { Set(sources.map(\.ref)) }

    /// Whether the given [start, end) range is fully covered by the cached window.
    public func covers(start: Date, end: Date) -> Bool {
        start >= windowStart && end <= windowEnd
    }

    /// Whether every one of `refs` was fetched into this file.
    ///
    /// Coverage is two-dimensional now that events are fetched on demand: a widget can ask for a
    /// range that *is* cached, on a calendar nobody had selected when the cache was written. That
    /// happens every time the user adds a calendar in Edit Widget, so the render path has to
    /// notice it the same way it notices a date-range shortfall.
    public func covers(refs: Set<CalendarRef>) -> Bool {
        refs.isSubset(of: coveredRefs)
    }

    /// The events one widget instance should consider: restricted to its calendar selection
    /// (nil ⇒ every calendar in the cache) and, unless `showDeclined`, with declined events
    /// dropped.
    ///
    /// Single definition of "visible" on purpose. This pair of predicates used to be written
    /// out separately in the grid builder, the agenda ordering, and the agenda's reload
    /// scheduling — and the third one drifting from the other two would schedule widget reloads
    /// for events the widget doesn't actually render.
    public func visibleEvents(refs: Set<CalendarRef>?, showDeclined: Bool) -> [CalendarEvent] {
        events.filter { event in
            if let refs, !refs.contains(event.ref) { return false }
            return showDeclined || !event.isDeclined
        }
    }

    /// Whether a widget instance should prompt the user to pick calendars instead of rendering.
    ///
    /// A non-nil but *empty* selection means the widget was placed and never configured; nil means
    /// "show every calendar" and is what the previews and the gallery use. `hasUnresolvable`
    /// covers a widget configured before multi-account, whose stored ids carry no account and so
    /// name no calendar we can find — same prompt, since the fix is the same.
    ///
    /// Gated on the **catalog**, not the events cache: calendars are pickable as soon as the
    /// accounts have been listed, and with demand-driven fetching nothing is fetched until
    /// something is picked. Gating on the events cache would deadlock exactly there.
    ///
    /// Static, and taking the catalog as an optional, because both entry builders need exactly
    /// this decision and had it written out separately with the reasoning copy-pasted alongside.
    public static func needsConfiguration(
        refs: Set<CalendarRef>?,
        hasUnresolvable: Bool,
        catalog: CalendarCatalog?
    ) -> Bool {
        guard catalog != nil else { return false }
        if hasUnresolvable { return true }
        return refs?.isEmpty == true
    }

    /// Re-adds `accounts`' events from the previous cache, clipped to this cache's window.
    ///
    /// The multi-account form of "a total sync failure must not be written". With one account,
    /// every calendar failing meant the whole sync failed and the write was skipped. With
    /// several, one account can be entirely unreachable — a revoked token, most often — while the
    /// others answer fine, and writing that result produces a cache that looks freshly synced
    /// with every widget on the dead account blank. Callers detect that case from
    /// `SyncResult.failedRefs` and carry the account forward instead.
    ///
    /// Clipping to the window is what keeps "exactly one canonical range, so nothing needs
    /// pruning" true — carried-forward events can't extend the cache past the range this sync
    /// asked for. The overlap test mirrors Google's own: `timeMin` bounds an event's *end* and
    /// `timeMax` its start, so a trip that began before the window is kept, exactly as a fetch
    /// would have returned it.
    public func carryingForward(accounts: Set<String>, from previous: EventCacheData) -> EventCacheData {
        guard !accounts.isEmpty else { return self }
        let revived = previous.events.filter {
            accounts.contains($0.accountEmail) && $0.endDate > windowStart && $0.startDate < windowEnd
        }
        guard !revived.isEmpty else { return self }
        var copy = self
        copy.events = (events + revived).sorted { $0.startDate < $1.startDate }
        return copy
    }

    /// PAGINATION path: widen the cache to include a freshly fetched range, merging in
    /// its events/sources without discarding what's already cached. De-dupes by
    /// `CalendarEvent.cacheKey` (incoming wins). Use when the user pages into a range not yet
    /// cached.
    ///
    /// The key is account + calendar + id, not id alone: the same meeting reachable through two
    /// calendars (or through two accounts) returns once per route under the same id, and those are
    /// separate rows the widget draws in separate colors. Keying on id merged them into one and
    /// handed the survivor whichever calendar arrived last, so paging into an uncached window
    /// silently dropped a copy and could recolor the other. The canonical path never had this —
    /// it replaces wholesale and de-dupes nothing.
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

        var sourcesByRef: [CalendarRef: CalendarSource] = [:]
        for s in sources { sourcesByRef[s.ref] = s }
        for s in newSources { sourcesByRef[s.ref] = s }

        // Sorts are cosmetic — they keep output deterministic for tests. Events tie-break on the
        // cache key because start date alone isn't a total order: the duplicates this merge now
        // preserves are the *same* meeting in two calendars, so they share a start exactly, and
        // ordering them by dictionary iteration would vary run to run.
        return EventCacheData(
            generatedAt: now,
            windowStart: min(windowStart, rangeStart),
            windowEnd: max(windowEnd, rangeEnd),
            sources: sourcesByRef.values.sorted { ($0.accountEmail, $0.id) < ($1.accountEmail, $1.id) },
            events: eventsByKey.values.sorted {
                ($0.startDate, $0.accountEmail, $0.calendarId, $0.id)
                    < ($1.startDate, $1.accountEmail, $1.calendarId, $1.id)
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
