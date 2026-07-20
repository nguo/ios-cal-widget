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
