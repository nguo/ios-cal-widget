import WidgetKit
import Foundation
import CalCore

/// Reads the pre-built cache + that variant's stored agenda offset and produces timeline entries,
/// scoped to this widget instance's calendar selection (`SelectCalendarsIntent`). Does no
/// networking — the render path only touches the App Group cache.
///
/// Shared by both agenda widgets; `variant` selects the offset key and the page sizing.
struct AgendaTimelineProvider: AppIntentTimelineProvider {
    var variant: AgendaVariant = .small

    func placeholder(in context: Context) -> AgendaEntry {
        // Placeholder always uses sample data (real cache may not exist in the gallery).
        WidgetFixtures.agendaEntry(variant: variant)
    }

    func snapshot(for configuration: SelectCalendarsIntent, in context: Context) async -> AgendaEntry {
        AgendaEntryBuilder.live(calendarIds: configuration.selectedCalendarIds,
                                showDeclined: configuration.showDeclinedEvents, variant: variant)
    }

    func timeline(for configuration: SelectCalendarsIntent, in context: Context) async -> Timeline<AgendaEntry> {
        let ids = configuration.selectedCalendarIds
        let showDeclined = configuration.showDeclinedEvents
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
            references += AgendaEntryBuilder.upcomingEndTimes(after: now, before: tomorrow, cache: cache, calendarIds: ids, showDeclined: showDeclined)
        }
        let entries = references.map {
            AgendaEntryBuilder.live(calendarIds: ids, showDeclined: showDeclined, variant: variant, reference: $0)
        }

        return Timeline(entries: entries, policy: .after(tomorrow))
    }
}
