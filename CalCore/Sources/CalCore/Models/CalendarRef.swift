import Foundation

/// What actually identifies a calendar once more than one Google account is signed in: the
/// account plus Google's calendarId.
///
/// `calendarId` alone does not. Google's ids are only unique *within* an account, and the
/// overlaps are the common cases rather than exotic ones — every account sees
/// `en.usa#holiday@group.v.calendar.google.com` under that exact id, and a calendar shared with
/// two of your accounts carries one id in both. Keying a filter, a selection, or a de-dupe on
/// `calendarId` therefore merges two genuinely different calendars, which is the same mistake
/// `CalendarEvent.CacheKey` exists to prevent one level down.
///
/// `encoded` is the wire form for places that can only carry a plain string: `AppIntent`
/// parameters (widget configuration, the paging intents) and the demanded-refs mirror in
/// `AppGroupStore`.
public struct CalendarRef: Hashable, Codable, Sendable {
    public let accountEmail: String
    public let calendarId: String

    public init(accountEmail: String, calendarId: String) {
        self.accountEmail = accountEmail
        self.calendarId = calendarId
    }

    /// Separator chosen because neither an email address nor a Google calendarId contains it —
    /// both are drawn from the email grammar, which has no "|". Parsing splits on the *first*
    /// one regardless, so a stray separator in a calendarId still round-trips.
    private static let separator: Character = "|"

    public var encoded: String { "\(accountEmail)\(Self.separator)\(calendarId)" }

    /// Fails on a string that carries no account — which is exactly what a widget configured
    /// before multi-account has stored. That nil is load-bearing: it's what makes such a widget
    /// show the reconfigure prompt instead of silently resolving to whichever account happens to
    /// own a matching calendarId.
    public init?(encoded: String) {
        guard let split = encoded.firstIndex(of: Self.separator) else { return nil }
        let account = String(encoded[encoded.startIndex ..< split])
        let id = String(encoded[encoded.index(after: split)...])
        guard !account.isEmpty, !id.isEmpty else { return nil }
        self.init(accountEmail: account, calendarId: id)
    }
}
