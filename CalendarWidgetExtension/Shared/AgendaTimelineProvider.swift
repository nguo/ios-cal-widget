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
        let now = Date()
        let cal = Calendar.current
        // Data reloads are pushed by syncs/intents; this fallback reload lands at the next
        // midnight so "today" (and the day list anchored to it) advances at the day boundary.
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)

        // One entry per moment the visible set changes: now, plus each event-end before midnight.
        // Each entry is built as-of its own instant, so WidgetKit swaps to it (dropping the ended
        // event) at that time with no networking and no refresh-budget cost.
        var references = [now]
        if let cache = EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read() {
            references += AgendaEntryBuilder.upcomingEndTimes(after: now, before: tomorrow, cache: cache)
        }
        let entries = references.map { AgendaEntryBuilder.live(reference: $0) }

        completion(Timeline(entries: entries, policy: .after(tomorrow)))
    }
}
