import XCTest
@testable import CalCore

/// The failure modes that only exist once a second Google account is signed in. Every one of
/// these is invisible with one account and silently wrong with two.
final class CalendarRefTests: XCTestCase {

    func testEncodeParseRoundTrip() {
        let ref = CalendarRef(accountEmail: "me@example.com",
                              calendarId: "en.usa#holiday@group.v.calendar.google.com")
        XCTAssertEqual(CalendarRef(encoded: ref.encoded), ref)
    }

    /// A widget configured before multi-account stored a bare calendarId. It must not resolve:
    /// picking whichever account owns a matching id would show a calendar the user never chose.
    func testUnqualifiedValueDoesNotParse() {
        XCTAssertNil(CalendarRef(encoded: "primary"))
        XCTAssertNil(CalendarRef(encoded: "en.usa#holiday@group.v.calendar.google.com"))
    }

    func testEmptyHalvesDoNotParse() {
        XCTAssertNil(CalendarRef(encoded: "|cal1"))
        XCTAssertNil(CalendarRef(encoded: "me@example.com|"))
        XCTAssertNil(CalendarRef(encoded: ""))
    }

    /// Splitting on the first separator, not the last, so a calendarId containing one still
    /// round-trips rather than swallowing part of the account.
    func testSplitsOnFirstSeparator() {
        let ref = CalendarRef(encoded: "me@example.com|weird|id")
        XCTAssertEqual(ref?.accountEmail, "me@example.com")
        XCTAssertEqual(ref?.calendarId, "weird|id")
    }
}

final class MultiAccountCacheTests: XCTestCase {
    private let cal = TestSupport.calendar()

    /// The collision that motivates `CalendarRef`: every Google account sees the US holidays
    /// calendar under the *same* id. Filtering by calendarId alone shows both accounts' copies to
    /// a widget that selected one.
    func testVisibleEventsSeparatesTheSameCalendarIdAcrossAccounts() {
        let start = TestSupport.date(2026, 3, 2, 9, calendar: cal)
        let end = TestSupport.date(2026, 3, 2, 10, calendar: cal)
        let holidays = "en.usa#holiday@group.v.calendar.google.com"

        let personal = TestSupport.event(id: "h1", title: "Holiday", start: start, end: end,
                                         calendarId: holidays, accountEmail: "me@example.com")
        let work = TestSupport.event(id: "h1", title: "Holiday", start: start, end: end,
                                     calendarId: holidays, accountEmail: "work@example.com")
        let cache = EventCacheData(generatedAt: start, windowStart: start, windowEnd: end,
                                   sources: [], events: [personal, work])

        let visible = cache.visibleEvents(
            refs: [TestSupport.ref(holidays, account: "me@example.com")], showDeclined: true
        )
        XCTAssertEqual(visible.map(\.accountEmail), ["me@example.com"])
    }

    /// Same root cause one level down: the two copies share `(calendarId, id)`, so a de-dupe that
    /// stops at the calendar collapses them and the survivor wears one account's color.
    func testAppendingKeepsTheSameEventReachedThroughTwoAccounts() {
        let s0 = TestSupport.date(2026, 3, 1, 0, calendar: cal)
        let e0 = TestSupport.date(2026, 3, 15, 0, calendar: cal)
        let start = TestSupport.date(2026, 3, 2, 9, calendar: cal)
        let end = TestSupport.date(2026, 3, 2, 10, calendar: cal)

        let mine = TestSupport.event(id: "shared", title: "Standup", start: start, end: end,
                                     color: "#111111", calendarId: "team", accountEmail: "me@example.com")
        let theirs = TestSupport.event(id: "shared", title: "Standup", start: start, end: end,
                                       color: "#222222", calendarId: "team", accountEmail: "work@example.com")
        let original = EventCacheData(generatedAt: s0, windowStart: s0, windowEnd: e0,
                                      sources: [], events: [mine])
        let merged = original.appending(events: [theirs], sources: [],
                                        rangeStart: s0, rangeEnd: e0, generatedAt: s0)

        XCTAssertEqual(merged.events.count, 2)
        XCTAssertEqual(merged.events.first { $0.accountEmail == "me@example.com" }?.colorHex, "#111111")
        XCTAssertEqual(merged.events.first { $0.accountEmail == "work@example.com" }?.colorHex, "#222222")
    }

    /// Coverage gained a second dimension when events became demand-driven: a widget can ask for a
    /// range the cache holds, on a calendar it has never fetched. That is what happens the moment
    /// the user adds a calendar in Edit Widget, and nothing else would notice it.
    func testCoversRefsIsSeparateFromCoveringDates() {
        let s0 = TestSupport.date(2026, 3, 1, 0, calendar: cal)
        let e0 = TestSupport.date(2026, 3, 15, 0, calendar: cal)
        let cache = EventCacheData(generatedAt: s0, windowStart: s0, windowEnd: e0,
                                   sources: [TestSupport.source("work")], events: [])

        XCTAssertTrue(cache.covers(start: s0, end: e0))
        XCTAssertTrue(cache.covers(refs: [TestSupport.ref("work")]))
        XCTAssertTrue(cache.covers(refs: []), "an unconfigured widget is short of nothing")
        XCTAssertFalse(cache.covers(refs: [TestSupport.ref("personal")]))
        XCTAssertFalse(cache.covers(refs: [TestSupport.ref("work", account: "other@example.com")]),
                       "same calendarId under another account is a different calendar")
    }

    /// The multi-account form of "a total sync failure must not be written". One account revoked
    /// while another answers used to produce a cache that looked freshly synced with the dead
    /// account's widgets blank.
    func testCarryingForwardRevivesAnUnreachableAccount() {
        let s0 = TestSupport.date(2026, 3, 1, 0, calendar: cal)
        let e0 = TestSupport.date(2026, 3, 15, 0, calendar: cal)
        let start = TestSupport.date(2026, 3, 2, 9, calendar: cal)
        let end = TestSupport.date(2026, 3, 2, 10, calendar: cal)

        let stale = TestSupport.event(id: "old", title: "Standup", start: start, end: end,
                                      calendarId: "work", accountEmail: "work@example.com")
        let previous = EventCacheData(generatedAt: s0, windowStart: s0, windowEnd: e0,
                                      sources: [], events: [stale])
        let fresh = EventCacheData(generatedAt: s0, windowStart: s0, windowEnd: e0, sources: [],
                                   events: [TestSupport.event(id: "new", title: "Lunch", start: start,
                                                              end: end, accountEmail: "me@example.com")])

        let carried = fresh.carryingForward(accounts: ["work@example.com"], from: previous)
        XCTAssertEqual(Set(carried.events.map(\.id)), ["new", "old"])
        XCTAssertEqual(fresh.carryingForward(accounts: [], from: previous).events.map(\.id), ["new"])
    }

    /// Carried-forward events are clipped to the new window, which is what keeps "exactly one
    /// canonical range, so nothing needs pruning" true — otherwise a repeatedly-failing account
    /// would drag its whole history along forever.
    func testCarryingForwardClipsToTheNewWindow() {
        let windowStart = TestSupport.date(2026, 3, 10, 0, calendar: cal)
        let windowEnd = TestSupport.date(2026, 3, 20, 0, calendar: cal)

        let longGone = TestSupport.event(
            id: "gone", title: "Old", start: TestSupport.date(2026, 1, 5, 9, calendar: cal),
            end: TestSupport.date(2026, 1, 5, 10, calendar: cal), accountEmail: "work@example.com"
        )
        // A trip that started before the window still overlaps it, exactly as Google's own
        // timeMin/timeMax bounds would have returned it.
        let trip = TestSupport.event(
            id: "trip", title: "Trip", start: TestSupport.date(2026, 3, 8, 0, calendar: cal),
            end: TestSupport.date(2026, 3, 12, 0, calendar: cal), isAllDay: true,
            accountEmail: "work@example.com"
        )
        let previous = EventCacheData(generatedAt: windowStart, windowStart: longGone.startDate,
                                      windowEnd: windowEnd, sources: [], events: [longGone, trip])
        let fresh = EventCacheData(generatedAt: windowStart, windowStart: windowStart,
                                   windowEnd: windowEnd, sources: [], events: [])

        let carried = fresh.carryingForward(accounts: ["work@example.com"], from: previous)
        XCTAssertEqual(carried.events.map(\.id), ["trip"])
        XCTAssertEqual(carried.windowStart, windowStart, "carry-forward must not widen the window")
    }

    /// One flaky calendar is a partial failure and stays partial. Only an account that answered
    /// for nothing at all is treated as unreachable.
    func testUnreachableAccountsNeedsEveryCalendarToFail() {
        let demanded = [
            TestSupport.source("a", account: "me@example.com"),
            TestSupport.source("b", account: "me@example.com"),
            TestSupport.source("c", account: "work@example.com")
        ]
        let partial: Set<CalendarRef> = [TestSupport.ref("a", account: "me@example.com")]
        XCTAssertEqual(SyncCoordinator.unreachableAccounts(demanded: demanded, failedRefs: partial), [])

        let whole: Set<CalendarRef> = [TestSupport.ref("c", account: "work@example.com")]
        XCTAssertEqual(SyncCoordinator.unreachableAccounts(demanded: demanded, failedRefs: whole),
                       ["work@example.com"])
    }
}

final class CalendarCatalogTests: XCTestCase {

    private let catalog = TestSupport.catalog([
        TestSupport.source("a", account: "me@example.com", summary: "Personal"),
        TestSupport.source("b", account: "me@example.com", summary: "Fun"),
        TestSupport.source("a", account: "work@example.com", summary: "Work")
    ])

    func testAccountEmailsAreDistinctAndOrdered() {
        XCTAssertEqual(catalog.accountEmails, ["me@example.com", "work@example.com"])
    }

    func testResolveMatchesOnTheFullRefNotTheId() {
        let resolved = catalog.resolve([TestSupport.ref("a", account: "work@example.com")])
        XCTAssertEqual(resolved.map(\.summary), ["Work"])
        XCTAssertTrue(catalog.resolve([TestSupport.ref("gone")]).isEmpty,
                      "a calendar that went away just drops out")
    }

    /// Accounts are listed one at a time and any can fail. A failed listing must leave that
    /// account's calendars alone — dropping them empties half the picker and makes live widget
    /// selections unresolvable, which reads as the widget forgetting its calendars.
    func testReplacingTouchesOnlyOneAccount() {
        let updated = catalog.replacing(
            accountEmail: "me@example.com",
            with: [TestSupport.source("c", account: "me@example.com", summary: "New")],
            generatedAt: Date()
        )
        XCTAssertEqual(updated.sources(for: "me@example.com").map(\.summary), ["New"])
        XCTAssertEqual(updated.sources(for: "work@example.com").map(\.summary), ["Work"])
    }

    func testRemovingDropsTheAccountEntirely() {
        let updated = catalog.removing(accountEmail: "me@example.com", generatedAt: Date())
        XCTAssertEqual(updated.accountEmails, ["work@example.com"])
    }
}

final class AccountRegistryTests: XCTestCase {
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

    func testAccountEmailsPersistInOrder() {
        let store = AppGroupStore(defaults: defaults)
        XCTAssertEqual(store.accountEmails, [])
        store.accountEmails = ["me@example.com", "work@example.com"]
        XCTAssertEqual(AppGroupStore(defaults: defaults).accountEmails,
                       ["me@example.com", "work@example.com"])
    }

    func testDemandedRefsRoundTripThroughTheirEncodedForm() {
        let store = AppGroupStore(defaults: defaults)
        XCTAssertEqual(store.demandedCalendarRefs, [])
        let refs: Set<CalendarRef> = [
            TestSupport.ref("a"), TestSupport.ref("a", account: "work@example.com")
        ]
        store.demandedCalendarRefs = refs
        XCTAssertEqual(AppGroupStore(defaults: defaults).demandedCalendarRefs, refs)
    }
}
