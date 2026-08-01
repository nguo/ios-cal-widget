import Foundation

/// A Google calendar available to the user, used to resolve per-event color and to
/// populate each widget's per-instance calendar picker. `id` is Google's calendarId.
/// Selection is no longer stored here — it lives per-widget in the configuration intent;
/// the cache holds every available calendar (a superset) so instances can filter at render.
public struct CalendarSource: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    /// Which signed-in Google account owns this calendar (supports multi-account).
    public let accountEmail: String
    public let summary: String
    /// Google's `backgroundColor` for the calendar, e.g. "#7986CB".
    public let colorHex: String
    /// True when this calendar is shared with you as free/busy only. Its events arrive with no
    /// title (and no other detail), so the mapper labels them "Busy" rather than "(No title)" —
    /// which is what Google Calendar itself shows, and the difference is meaningful: one means
    /// "you may not see this", the other means "nobody named it".
    public let isFreeBusyOnly: Bool

    public init(
        id: String,
        accountEmail: String,
        summary: String,
        colorHex: String,
        isFreeBusyOnly: Bool = false
    ) {
        self.id = id
        self.accountEmail = accountEmail
        self.summary = summary
        self.colorHex = colorHex
        self.isFreeBusyOnly = isFreeBusyOnly
    }

    private enum CodingKeys: String, CodingKey {
        case id, accountEmail, summary, colorHex, isFreeBusyOnly
    }

    /// Custom decode so caches written before `isFreeBusyOnly` existed still load — same reason
    /// `CalendarEvent` does it for `htmlLink` / `isDeclined`. Encoding stays synthesized.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        accountEmail = try c.decode(String.self, forKey: .accountEmail)
        summary = try c.decode(String.self, forKey: .summary)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        isFreeBusyOnly = try c.decodeIfPresent(Bool.self, forKey: .isFreeBusyOnly) ?? false
    }
}
