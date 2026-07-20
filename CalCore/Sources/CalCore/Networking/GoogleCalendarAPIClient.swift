import Foundation

/// Thin REST client for the two Google Calendar endpoints we need. Raw `URLSession` +
/// `Codable` — deliberately no generated Google API client, to keep the widget extension
/// light. Paginates `nextPageToken` internally and surfaces `nextSyncToken` for incremental
/// syncs.
public struct GoogleCalendarAPIClient {
    private let transport: HTTPTransport
    static let base = URL(string: "https://www.googleapis.com/calendar/v3")!

    public init(transport: HTTPTransport = URLSession.shared) {
        self.transport = transport
    }

    /// The user's calendar list (for the picker), including each calendar's color.
    public func calendarList(accessToken: String) async throws -> [GCalCalendarListEntry] {
        var entries: [GCalCalendarListEntry] = []
        var pageToken: String?
        repeat {
            var items = [URLQueryItem(name: "minAccessRole", value: "reader")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let url = try Self.makeURL(encodedPath: "/users/me/calendarList", query: items)
            let resp: GCalCalendarListResponse = try await get(url, accessToken: accessToken)
            entries.append(contentsOf: resp.items)
            pageToken = resp.nextPageToken
        } while pageToken != nil
        return entries
    }

    public struct EventsPage: Sendable {
        public let events: [GCalEvent]
        public let nextSyncToken: String?
    }

    /// Events for one calendar in a time range, expanding recurrences (`singleEvents`),
    /// following pagination. Pass `syncToken` from a prior fetch for an incremental update
    /// (Google then ignores timeMin/timeMax).
    public func events(
        calendarId: String,
        accessToken: String,
        timeMin: Date? = nil,
        timeMax: Date? = nil,
        syncToken: String? = nil
    ) async throws -> EventsPage {
        var all: [GCalEvent] = []
        var pageToken: String?
        var latestSyncToken: String?
        let iso = ISO8601Parsers.query

        repeat {
            var items = [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "2500")
            ]
            if let syncToken {
                items.append(URLQueryItem(name: "syncToken", value: syncToken))
            } else {
                if let timeMin { items.append(URLQueryItem(name: "timeMin", value: iso.string(from: timeMin))) }
                if let timeMax { items.append(URLQueryItem(name: "timeMax", value: iso.string(from: timeMax))) }
            }
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }

            let url = try Self.makeURL(encodedPath: Self.eventsPath(calendarId: calendarId), query: items)
            let resp: GCalEventsResponse = try await get(url, accessToken: accessToken)
            all.append(contentsOf: resp.items)
            pageToken = resp.nextPageToken
            if let t = resp.nextSyncToken { latestSyncToken = t }
        } while pageToken != nil

        return EventsPage(events: all, nextSyncToken: latestSyncToken)
    }

    // MARK: - Helpers

    /// RFC 3986 `pchar` minus "/" — the characters legal inside a single path segment.
    /// Notably excludes "#" and "/", both of which occur in real calendar ids.
    private static let pathSegmentAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~!$&'()*+,;=:@")
        return set
    }()

    /// Percent-encodes one path segment. Google calendar ids routinely contain "#"
    /// (`en.usa#holiday@group.v.calendar.google.com`, `#contacts@group.v.calendar.google.com`).
    ///
    /// Public only so the off-device harness can assert it — same seam as
    /// `TokenRefreshService.formURLEncode`.
    public static func encodePathSegment(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? segment
    }

    /// The events-list path for one calendar, with the id safely escaped. Split out so the
    /// encoding can be asserted off-device (see `calcore-check`).
    public static func eventsPath(calendarId: String) -> String {
        "/calendars/\(encodePathSegment(calendarId))/events"
    }

    /// Appends an **already percent-encoded** path to the API base.
    ///
    /// Assigns `percentEncodedPath` rather than calling `appendingPathComponent`, which
    /// re-encodes its argument: the "%" of an escaped segment became "%25", turning a
    /// calendar id's "%23" into "%2523". Every holiday and contacts calendar 404'd, and
    /// because a per-calendar fetch failure is swallowed, they simply rendered empty forever.
    public static func makeURL(encodedPath: String, query: [URLQueryItem]) throws -> URL {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw HTTPError.invalidURL
        }
        comps.percentEncodedPath += encodedPath
        comps.queryItems = query
        guard let url = comps.url else { throw HTTPError.invalidURL }
        return url
    }

    private func get<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.nonHTTPResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw HTTPError.status(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
