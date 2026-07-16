import WidgetKit
import Foundation
import CalCore

/// Reads the pre-built cache + shared agenda offset and produces timeline entries.
/// Does no networking — the render path only touches the App Group cache.
struct AgendaTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        // Placeholder always uses sample data (real cache may not exist in the gallery).
        WidgetFixtures.agendaEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        completion(AgendaEntryBuilder.live())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        let entry = AgendaEntryBuilder.live()
        // Data reloads are pushed by syncs/intents; this fallback reload lands at the next
        // midnight so "today" (and the day list anchored to it) advances at the day boundary.
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }
}
