import XCTest
@testable import CalCore

final class EventCacheTests: XCTestCase {
    let cal = TestSupport.calendar()

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("events.json")
    }

    func testWriteThenReadRoundTrips() throws {
        let url = tempFile()
        let cache = EventCache(fileURL: url)
        let start = TestSupport.date(2026, 3, 1, 0, 0, calendar: cal)
        let end = TestSupport.date(2026, 3, 15, 0, 0, calendar: cal)
        let e = TestSupport.event(id: "1", title: "Lunch",
                                  start: TestSupport.date(2026, 3, 14, 12, calendar: cal),
                                  end: TestSupport.date(2026, 3, 14, 13, calendar: cal))
        let data = EventCacheData(generatedAt: start, windowStart: start, windowEnd: end,
                                  sources: [], events: [e])

        try cache.write(data)
        let read = try XCTUnwrap(cache.read())
        XCTAssertEqual(read, data)
    }

    func testWriteIsAtomicAndCreatesDirectory() throws {
        // fileURL is in a non-existent subdirectory; write should create it.
        let url = tempFile()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        let cache = EventCache(fileURL: url)
        let now = Date()
        try cache.write(EventCacheData(generatedAt: now, windowStart: now, windowEnd: now, sources: [], events: []))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testReadMissingFileReturnsNil() {
        let cache = EventCache(fileURL: tempFile())
        XCTAssertNil(cache.read())
    }

    func testCoversRange() {
        let data = EventCacheData(
            generatedAt: Date(),
            windowStart: TestSupport.date(2026, 3, 1, 0, calendar: cal),
            windowEnd: TestSupport.date(2026, 4, 1, 0, calendar: cal),
            sources: [], events: []
        )
        XCTAssertTrue(data.covers(start: TestSupport.date(2026, 3, 10, 0, calendar: cal),
                                  end: TestSupport.date(2026, 3, 20, 0, calendar: cal)))
        XCTAssertFalse(data.covers(start: TestSupport.date(2026, 2, 20, 0, calendar: cal),
                                   end: TestSupport.date(2026, 3, 20, 0, calendar: cal)))
    }

    // MARK: - Merge behaviors

    func testAppendingWidensWindowAndMergesEvents() {
        let s0 = TestSupport.date(2026, 3, 1, 0, calendar: cal)
        let e0 = TestSupport.date(2026, 3, 15, 0, calendar: cal)
        let ev1 = TestSupport.event(id: "1", title: "One",
            start: TestSupport.date(2026, 3, 2, 9, calendar: cal),
            end: TestSupport.date(2026, 3, 2, 10, calendar: cal))
        let original = EventCacheData(generatedAt: s0, windowStart: s0, windowEnd: e0,
                                      sources: [], events: [ev1])

        let newStart = e0
        let newEnd = TestSupport.date(2026, 3, 29, 0, calendar: cal)
        let ev2 = TestSupport.event(id: "2", title: "Two",
            start: TestSupport.date(2026, 3, 20, 9, calendar: cal),
            end: TestSupport.date(2026, 3, 20, 10, calendar: cal))

        let merged = original.appending(events: [ev2], sources: [], rangeStart: newStart, rangeEnd: newEnd, generatedAt: Date())
        XCTAssertEqual(merged.windowStart, s0)
        XCTAssertEqual(merged.windowEnd, newEnd, "window should widen forward")
        XCTAssertEqual(Set(merged.events.map(\.id)), ["1", "2"])
    }

    func testAppendingDedupesByIdIncomingWins() {
        let s0 = TestSupport.date(2026, 3, 1, 0, calendar: cal)
        let e0 = TestSupport.date(2026, 3, 15, 0, calendar: cal)
        let stale = TestSupport.event(id: "1", title: "Stale Title",
            start: TestSupport.date(2026, 3, 2, 9, calendar: cal),
            end: TestSupport.date(2026, 3, 2, 10, calendar: cal))
        let original = EventCacheData(generatedAt: s0, windowStart: s0, windowEnd: e0, sources: [], events: [stale])

        let fresh = TestSupport.event(id: "1", title: "Fresh Title",
            start: TestSupport.date(2026, 3, 2, 9, calendar: cal),
            end: TestSupport.date(2026, 3, 2, 10, calendar: cal))
        let merged = original.appending(events: [fresh], sources: [], rangeStart: s0, rangeEnd: e0, generatedAt: Date())

        XCTAssertEqual(merged.events.count, 1)
        XCTAssertEqual(merged.events.first?.title, "Fresh Title", "incoming event should win the de-dupe")
    }

    /// The same meeting reachable through two calendars comes back once per calendar under the
    /// same Google event id. They are two rows the widget draws in two colors, so the merge must
    /// keep both — keying on `id` alone collapsed them and, since incoming wins, left the single
    /// survivor wearing whichever calendar's color happened to arrive last.
    func testAppendingKeepsSameIdOnDifferentCalendars() {
        let s0 = TestSupport.date(2026, 3, 1, 0, calendar: cal)
        let e0 = TestSupport.date(2026, 3, 15, 0, calendar: cal)
        let start = TestSupport.date(2026, 3, 2, 9, calendar: cal)
        let end = TestSupport.date(2026, 3, 2, 10, calendar: cal)

        let onWork = TestSupport.event(id: "shared", title: "Standup", start: start, end: end,
                                       color: "#111111", calendarId: "work")
        let original = EventCacheData(generatedAt: s0, windowStart: s0, windowEnd: e0,
                                      sources: [], events: [onWork])

        // Same event id, different calendar — a distinct row, not a restatement of the first.
        let onPersonal = TestSupport.event(id: "shared", title: "Standup", start: start, end: end,
                                           color: "#222222", calendarId: "personal")
        let merged = original.appending(events: [onPersonal], sources: [],
                                        rangeStart: s0, rangeEnd: e0, generatedAt: Date())

        XCTAssertEqual(merged.events.count, 2, "both calendars' copies should survive the merge")
        XCTAssertEqual(Set(merged.events.map(\.calendarId)), ["work", "personal"])
        // The colors must stay attached to their own calendar; collapsing recolored one of them.
        XCTAssertEqual(merged.events.first { $0.calendarId == "work" }?.colorHex, "#111111")
        XCTAssertEqual(merged.events.first { $0.calendarId == "personal" }?.colorHex, "#222222")
    }

    /// Re-fetching one calendar must still replace that calendar's copy — the wider key must not
    /// turn the de-dupe off, or paging back and forth would accumulate stale duplicates.
    func testAppendingStillDedupesWithinOneCalendar() {
        let s0 = TestSupport.date(2026, 3, 1, 0, calendar: cal)
        let e0 = TestSupport.date(2026, 3, 15, 0, calendar: cal)
        let start = TestSupport.date(2026, 3, 2, 9, calendar: cal)
        let end = TestSupport.date(2026, 3, 2, 10, calendar: cal)

        let onWork = TestSupport.event(id: "shared", title: "Standup", start: start, end: end, calendarId: "work")
        let onPersonal = TestSupport.event(id: "shared", title: "Standup", start: start, end: end, calendarId: "personal")
        let original = EventCacheData(generatedAt: s0, windowStart: s0, windowEnd: e0,
                                      sources: [], events: [onWork, onPersonal])

        let renamed = TestSupport.event(id: "shared", title: "Standup (moved)", start: start, end: end, calendarId: "work")
        let merged = original.appending(events: [renamed], sources: [],
                                        rangeStart: s0, rangeEnd: e0, generatedAt: Date())

        XCTAssertEqual(merged.events.count, 2, "the refetched copy replaces its own, not the other calendar's")
        XCTAssertEqual(merged.events.first { $0.calendarId == "work" }?.title, "Standup (moved)")
        XCTAssertEqual(merged.events.first { $0.calendarId == "personal" }?.title, "Standup")
    }

    /// Duplicates that survive share a start date exactly, so start alone can't order them and
    /// dictionary iteration would vary between runs.
    func testAppendingOrdersTiedStartsDeterministically() {
        let s0 = TestSupport.date(2026, 3, 1, 0, calendar: cal)
        let e0 = TestSupport.date(2026, 3, 15, 0, calendar: cal)
        let start = TestSupport.date(2026, 3, 2, 9, calendar: cal)
        let end = TestSupport.date(2026, 3, 2, 10, calendar: cal)

        let incoming = ["work", "personal", "team", "family"].map {
            TestSupport.event(id: "shared", title: "Standup", start: start, end: end, calendarId: $0)
        }
        let empty = EventCacheData(generatedAt: s0, windowStart: s0, windowEnd: e0, sources: [], events: [])

        let first = empty.appending(events: incoming, sources: [], rangeStart: s0, rangeEnd: e0, generatedAt: s0)
        for _ in 0 ..< 20 {
            let again = empty.appending(events: incoming.shuffled(), sources: [],
                                        rangeStart: s0, rangeEnd: e0, generatedAt: s0)
            XCTAssertEqual(again.events.map(\.calendarId), first.events.map(\.calendarId))
        }
    }
}
