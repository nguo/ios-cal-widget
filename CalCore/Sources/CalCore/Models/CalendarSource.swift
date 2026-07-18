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

    public init(
        id: String,
        accountEmail: String,
        summary: String,
        colorHex: String
    ) {
        self.id = id
        self.accountEmail = accountEmail
        self.summary = summary
        self.colorHex = colorHex
    }
}
