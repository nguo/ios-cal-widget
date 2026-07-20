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
}
