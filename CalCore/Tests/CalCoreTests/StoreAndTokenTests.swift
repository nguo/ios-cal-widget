import XCTest
@testable import CalCore

final class AppGroupStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testPageOffsetDefaultsToZeroAndPersists() {
        let store = AppGroupStore(defaults: defaults)
        XCTAssertEqual(store.pageOffset, 0)
        store.pageOffset = -1
        XCTAssertEqual(AppGroupStore(defaults: defaults).pageOffset, -1)
    }

    func testIsSyncingFlag() {
        let store = AppGroupStore(defaults: defaults)
        XCTAssertFalse(store.isSyncing)
        store.isSyncing = true
        XCTAssertTrue(AppGroupStore(defaults: defaults).isSyncing)
    }

    func testSelectedCalendarIdsRoundTrip() {
        let store = AppGroupStore(defaults: defaults)
        XCTAssertEqual(store.selectedCalendarIds, [])
        store.selectedCalendarIds = ["a@group.calendar.google.com", "b"]
        XCTAssertEqual(AppGroupStore(defaults: defaults).selectedCalendarIds, ["a@group.calendar.google.com", "b"])
    }
}

final class TokenRefreshTests: XCTestCase {
    func testFormURLEncodingIsSortedAndEscaped() {
        let encoded = TokenRefreshService.formURLEncode([
            "grant_type": "refresh_token",
            "refresh_token": "a b/c",
            "client_id": "id"
        ])
        // Sorted by key: client_id, grant_type, refresh_token; space/slash escaped.
        XCTAssertEqual(encoded, "client_id=id&grant_type=refresh_token&refresh_token=a%20b%2Fc")
    }

    func testValidateRejectsNon2xx() {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        let response = HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try TokenRefreshService.validate(response, data: Data("bad".utf8))) { error in
            XCTAssertEqual(error as? HTTPError, .status(400, body: "bad"))
        }
    }

    func testAccessTokenParsesAndComputesExpiry() async throws {
        let stub = StubTransport(body: Data("""
        {"access_token":"ya29.abc","expires_in":3600,"token_type":"Bearer"}
        """.utf8), statusCode: 200)
        let service = TokenRefreshService(clientID: "id", transport: stub)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let token = try await service.accessToken(refreshToken: "refresh", now: now)
        XCTAssertEqual(token.token, "ya29.abc")
        XCTAssertEqual(token.expiresAt, now.addingTimeInterval(3600))
    }
}

/// Simple in-memory transport for testing network callers without hitting the network.
struct StubTransport: HTTPTransport {
    let body: Data
    let statusCode: Int
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil
        )!
        return (body, response)
    }
}
