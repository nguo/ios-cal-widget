import XCTest
@testable import CalCore

/// Regression tests for the Phase 1 correctness fixes. Each one pins a failure mode that
/// shipped silently — no crash, no error, just wrong data on the widget.
final class CalendarIDEncodingTests: XCTestCase {

    /// Holiday and contacts calendars carry a "#" in their id. It must survive as exactly one
    /// "%23": the old path percent-encoded the id and then handed it to
    /// `appendingPathComponent`, which re-encoded the "%" into "%25" and produced "%2523".
    /// Google 404'd, the per-calendar error was swallowed, and those calendars rendered empty
    /// forever with no visible failure.
    func testHashInCalendarIDIsEncodedExactlyOnce() throws {
        let id = "en.usa#holiday@group.v.calendar.google.com"
        let url = try GoogleCalendarAPIClient.makeURL(
            encodedPath: GoogleCalendarAPIClient.eventsPath(calendarId: id),
            query: [URLQueryItem(name: "singleEvents", value: "true")]
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://www.googleapis.com/calendar/v3/calendars/"
            + "en.usa%23holiday@group.v.calendar.google.com/events?singleEvents=true"
        )
        XCTAssertFalse(url.absoluteString.contains("%2523"), "id was double-encoded")
    }

    func testLeadingHashCalendarID() {
        XCTAssertEqual(
            GoogleCalendarAPIClient.eventsPath(calendarId: "#contacts@group.v.calendar.google.com"),
            "/calendars/%23contacts@group.v.calendar.google.com/events"
        )
    }

    /// A "/" would otherwise split the path and address a different endpoint entirely.
    func testSlashInCalendarIDIsEscaped() {
        XCTAssertEqual(
            GoogleCalendarAPIClient.eventsPath(calendarId: "a/b"),
            "/calendars/a%2Fb/events"
        )
    }

    func testOrdinaryCalendarIDIsUnchanged() {
        XCTAssertEqual(
            GoogleCalendarAPIClient.eventsPath(calendarId: "me@gmail.com"),
            "/calendars/me@gmail.com/events"
        )
    }
}

final class TrustedHostTests: XCTestCase {

    func testAcceptsGoogleAndSubdomains() {
        for string in [
            "https://google.com/calendar",
            "https://calendar.google.com/calendar/u/0/r/day/2026/7/19",
            "https://www.google.com/calendar/event?eid=abc"
        ] {
            XCTAssertTrue(DeepLinkBuilder.isTrustedGoogleHost(URL(string: string)!), string)
        }
    }

    /// The bug this replaced: `hasSuffix("google.com")` matches any host *ending* in those
    /// characters, so an attacker-registered `evilgoogle.com` passed the check.
    func testRejectsLookalikeHosts() {
        for string in [
            "https://evilgoogle.com/calendar",
            "https://notgoogle.com",
            "https://google.com.attacker.net",
            "https://attacker.net/?x=google.com"
        ] {
            XCTAssertFalse(DeepLinkBuilder.isTrustedGoogleHost(URL(string: string)!), string)
        }
    }

    func testRejectsNonHTTPSSchemes() {
        for string in [
            "http://calendar.google.com",
            "javascript://google.com/%0aalert(1)",
            "file:///etc/passwd"
        ] {
            XCTAssertFalse(DeepLinkBuilder.isTrustedGoogleHost(URL(string: string)!), string)
        }
    }
}

final class BuildCacheFailureTests: XCTestCase {
    private let cal = TestSupport.calendar()

    private func sources(_ count: Int) -> [CalendarSource] {
        (0 ..< count).map {
            CalendarSource(id: "cal\($0)", accountEmail: "me@example.com",
                           summary: "Cal \($0)", colorHex: "#000000")
        }
    }

    private func service(_ transport: HTTPTransport) -> CalendarSyncService {
        CalendarSyncService(api: GoogleCalendarAPIClient(transport: transport), calendar: cal)
    }

    /// The core Phase 1 fix: when every calendar fails, the sync must report failure rather
    /// than hand back a valid-looking cache with zero events. Writing that empty result
    /// blanked the widget while leaving it looking freshly synced.
    func testAllCalendarsFailingReturnsNil() async {
        let cache = await service(StubTransport(body: Data("nope".utf8), statusCode: 500))
            .buildCache(sources: sources(3), rangeStart: Date(), rangeEnd: Date(),
                        now: Date(), tokenProvider: { _ in "token" })
        XCTAssertNil(cache)
    }

    /// A failing *token provider* is the transient-network case: it fails before any request.
    func testTokenFailureReturnsNil() async {
        struct Boom: Error {}
        let cache = await service(StubTransport(body: Data("{}".utf8), statusCode: 200))
            .buildCache(sources: sources(2), rangeStart: Date(), rangeEnd: Date(),
                        now: Date(), tokenProvider: { _ in throw Boom() })
        XCTAssertNil(cache)
    }

    /// Partial failure keeps its existing behavior — some data beats none.
    func testPartialFailureStillReturnsCache() async {
        let transport = PerCalendarTransport(failing: ["cal0"])
        let cache = await service(transport)
            .buildCache(sources: sources(2), rangeStart: Date(), rangeEnd: Date(),
                        now: Date(), tokenProvider: { _ in "token" })
        XCTAssertNotNil(cache)
        XCTAssertEqual(cache?.events.map(\.calendarId), ["cal1"])
    }

    /// An empty calendar is not a failed one: a successful fetch returning no events must
    /// still produce a cache, or a genuinely empty schedule would look like an outage.
    func testGenuinelyEmptyCalendarsStillReturnCache() async {
        let empty = Data(#"{"items":[]}"#.utf8)
        let cache = await service(StubTransport(body: empty, statusCode: 200))
            .buildCache(sources: sources(2), rangeStart: Date(), rangeEnd: Date(),
                        now: Date(), tokenProvider: { _ in "token" })
        XCTAssertNotNil(cache)
        XCTAssertEqual(cache?.events.count, 0)
    }

    func testNoSourcesReturnsNil() async {
        let cache = await service(StubTransport(body: Data("{}".utf8), statusCode: 200))
            .buildCache(sources: [], rangeStart: Date(), rangeEnd: Date(),
                        now: Date(), tokenProvider: { _ in "token" })
        XCTAssertNil(cache)
    }

    /// Unbounded parallelism drew Google's rate limiter, which then read as calendars with no
    /// events. Cap the number of requests actually in flight at once.
    func testFetchConcurrencyIsBounded() async {
        let transport = ConcurrencyProbe()
        let service = CalendarSyncService(
            api: GoogleCalendarAPIClient(transport: transport), calendar: cal, maxConcurrentFetches: 3
        )
        _ = await service.buildCache(sources: sources(12), rangeStart: Date(), rangeEnd: Date(),
                                     now: Date(), tokenProvider: { _ in "token" })
        XCTAssertLessThanOrEqual(transport.peak, 3)
        XCTAssertEqual(transport.total, 12, "every calendar is still fetched")
    }

    func testRateLimitDetection() {
        XCTAssertTrue(CalendarSyncService.isRateLimited(HTTPError.status(429, body: "")))
        XCTAssertTrue(CalendarSyncService.isRateLimited(
            HTTPError.status(403, body: #"{"error":{"errors":[{"reason":"rateLimitExceeded"}]}}"#)))
        XCTAssertTrue(CalendarSyncService.isRateLimited(
            HTTPError.status(403, body: #"{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}"#)))
        // A plain permission failure is not retryable — retrying just burns the time budget.
        XCTAssertFalse(CalendarSyncService.isRateLimited(
            HTTPError.status(403, body: #"{"error":{"errors":[{"reason":"forbidden"}]}}"#)))
        XCTAssertFalse(CalendarSyncService.isRateLimited(HTTPError.status(500, body: "boom")))
        XCTAssertFalse(CalendarSyncService.isRateLimited(HTTPError.nonHTTPResponse))
    }

    /// A throttled calendar should come back on retry rather than silently vanishing.
    func testRateLimitedCalendarIsRetried() async {
        let transport = FailThenSucceed(failures: 1, statusCode: 429, body: "slow down")
        let cache = await service(transport).buildCache(
            sources: sources(1), rangeStart: Date(), rangeEnd: Date(),
            now: Date(), tokenProvider: { _ in "token" }
        )
        XCTAssertNotNil(cache)
        XCTAssertEqual(transport.attempts, 2)
    }

    /// Non-throttling errors must NOT be retried.
    func testServerErrorIsNotRetried() async {
        let transport = FailThenSucceed(failures: 1, statusCode: 500, body: "boom")
        _ = await service(transport).buildCache(
            sources: sources(1), rangeStart: Date(), rangeEnd: Date(),
            now: Date(), tokenProvider: { _ in "token" }
        )
        XCTAssertEqual(transport.attempts, 1)
    }
}

/// Records how many requests are in flight simultaneously.
private final class ConcurrencyProbe: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var peak = 0
    private(set) var total = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        current += 1
        total += 1
        peak = max(peak, current)
        lock.unlock()
        defer { lock.lock(); current -= 1; lock.unlock() }

        try? await Task.sleep(for: .milliseconds(20)) // hold the slot so overlap is observable
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(#"{"items":[]}"#.utf8), response)
    }
}

/// Fails the first `failures` requests with the given status, then succeeds.
private final class FailThenSucceed: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let failures: Int
    private let statusCode: Int
    private let body: String
    private(set) var attempts = 0

    init(failures: Int, statusCode: Int, body: String) {
        self.failures = failures
        self.statusCode = statusCode
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        attempts += 1
        let shouldFail = attempts <= failures
        lock.unlock()

        let code = shouldFail ? statusCode : 200
        let payload = shouldFail ? body : #"{"items":[]}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        return (Data(payload.utf8), response)
    }
}

/// Succeeds for every calendar except the named ones, which 500. Returns a single event whose
/// id encodes the calendar it came from, so tests can assert which fetches survived.
private struct PerCalendarTransport: HTTPTransport {
    let failing: Set<String>

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let calendarId = url.path
            .replacingOccurrences(of: "/calendar/v3/calendars/", with: "")
            .replacingOccurrences(of: "/events", with: "")
        let failed = failing.contains(calendarId)
        let body = failed ? Data("boom".utf8) : Data("""
        {"items":[{"id":"e-\(calendarId)","summary":"Event",
        "start":{"dateTime":"2026-07-19T10:00:00Z"},
        "end":{"dateTime":"2026-07-19T11:00:00Z"}}]}
        """.utf8)
        let response = HTTPURLResponse(
            url: url, statusCode: failed ? 500 : 200, httpVersion: nil, headerFields: nil
        )!
        return (body, response)
    }
}
