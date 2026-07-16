import Foundation

/// A Google calendar the user can select. Persisted (selection state) and used to
/// resolve per-event color. `id` is Google's calendarId.
public struct CalendarSource: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    /// Which signed-in Google account owns this calendar (supports multi-account).
    public let accountEmail: String
    public let summary: String
    /// Google's `backgroundColor` for the calendar, e.g. "#7986CB".
    public let colorHex: String
    public var isSelected: Bool

    public init(
        id: String,
        accountEmail: String,
        summary: String,
        colorHex: String,
        isSelected: Bool = false
    ) {
        self.id = id
        self.accountEmail = accountEmail
        self.summary = summary
        self.colorHex = colorHex
        self.isSelected = isSelected
    }
}
