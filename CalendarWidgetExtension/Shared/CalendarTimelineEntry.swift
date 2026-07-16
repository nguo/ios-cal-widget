import WidgetKit
import Foundation
import CalCore

/// One rendered snapshot of the widget: the visible window plus the events grouped by day.
struct CalendarTimelineEntry: TimelineEntry {
    let date: Date
    let window: DateWindow
    /// Events keyed by start-of-day, for each day in `window`.
    let eventsByDay: [Date: [CalendarEvent]]
    /// True if the requested window fell outside the cached range (show "tap to refresh").
    let cacheIsStale: Bool
    /// True while a sync is in flight (dims the refresh button).
    let isSyncing: Bool
    let lastSyncedAt: Date?
}
