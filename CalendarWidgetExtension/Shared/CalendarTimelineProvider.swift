import WidgetKit
import Foundation
import CalCore

/// Reads the pre-built cache + shared pagination offset and produces timeline entries.
/// Generic over `weekCount` so a future one-week/three-week widget reuses it unchanged.
/// Does no networking — the render path only touches the App Group cache.
struct CalendarTimelineProvider: TimelineProvider {
    let weekCount: Int

    func placeholder(in context: Context) -> CalendarTimelineEntry {
        // Placeholder always uses sample data (real cache may not exist in the gallery).
        WidgetFixtures.entry()
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarTimelineEntry) -> Void) {
        completion(CalendarEntryBuilder.live(weekCount: weekCount))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarTimelineEntry>) -> Void) {
        let entry = CalendarEntryBuilder.live(weekCount: weekCount)
        // Data reloads are pushed by syncs/intents; this fallback reload lands at the next
        // midnight so the "today" marker and the week anchor advance right at the day/week
        // boundary (offset-0 window re-derives from the new date).
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }
}
