import Foundation

/// Thin REST client for the two Google Calendar endpoints we need. Raw `URLSession` +
/// `Codable` — deliberately no generated Google API client, to keep the widget extension
/// light. Paginates `nextPageToken` internally and surfaces `nextSyncToken` for incremental
/// syncs.
public struct GoogleCalendarAPIClient {
    private let transport: HTTPTransport
    private let base = URL(string: "https://www.googleapis.com/calendar/v3")!

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
            let url = makeURL(path: "/users/me/calendarList", query: items)
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
        let iso = ISO8601DateFormatter()

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

            let encodedId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
            let url = makeURL(path: "/calendars/\(encodedId)/events", query: items)
            let resp: GCalEventsResponse = try await get(url, accessToken: accessToken)
            all.append(contentsOf: resp.items)
            pageToken = resp.nextPageToken
            if let t = resp.nextSyncToken { latestSyncToken = t }
        } while pageToken != nil

        return EventsPage(events: all, nextSyncToken: latestSyncToken)
    }

    // MARK: - Helpers

    private func makeURL(path: String, query: [URLQueryItem]) -> URL {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        return comps.url!
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
