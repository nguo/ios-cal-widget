import WidgetKit
import Foundation
import CalCore

/// Reads the pre-built cache + that variant's stored agenda offset and produces timeline entries,
/// scoped to this widget instance's calendar selection (`SelectCalendarsIntent`). Rendering itself
/// reads only the App Group cache; the sole network call is `CoverageRefresh`, when the reload
/// lands on a horizon the cache no longer covers.
///
/// Shared by both agenda widgets; `variant` selects the offset key and the page sizing.
struct AgendaTimelineProvider: AppIntentTimelineProvider {
    var variant: AgendaVariant = .small

    func placeholder(in context: Context) -> AgendaEntry {
        // Placeholder always uses sample data (real cache may not exist in the gallery).
        WidgetFixtures.agendaEntry(variant: variant)
    }

    func snapshot(for configuration: SelectCalendarsIntent, in context: Context) async -> AgendaEntry {
        // Gallery preview: sample data, since the real cache may be empty or absent.
        if context.isPreview { return WidgetFixtures.agendaEntry(variant: variant) }
        return AgendaEntryBuilder.live(calendarIds: configuration.selectedCalendarIds,
                                       showDeclined: configuration.showDeclinedEvents, variant: variant)
    }

    func timeline(for configuration: SelectCalendarsIntent, in context: Context) async -> Timeline<AgendaEntry> {
        let ids = configuration.selectedCalendarIds
        let showDeclined = configuration.showDeclinedEvents
        let now = Date()
        let cal = Calendar.calWidget
        // Data reloads are pushed by syncs/intents; this fallback reload lands at the next
        // midnight so "today" (and the day list anchored to it) advances at the day boundary.
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)

        // The one place this provider may touch the network. The agenda's horizon walks forward
        // with "today", but the cached window doesn't, so each midnight reload leaves it a day
        // shorter at the far edge until something syncs.
        let horizonEnd = cal.date(byAdding: .day, value: AppConfig.agendaHorizonDays, to: cal.startOfDay(for: now)) ?? now
        let refreshed = await CoverageRefresh.syncIfUncovered(
            start: cal.startOfDay(for: now), end: horizonEnd, calendar: cal, now: now
        )

        // Read the cache ONCE and thread it through every entry below. Each `live` call used to
        // re-open and re-decode the whole events.json, so a busy day cost a dozen-plus full
        // decodes per reload inside a memory-capped extension.
        let cache = refreshed ?? EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read()

        // One entry per moment the visible set changes: now, plus each event-end before midnight.
        // Each entry is built as-of its own instant, so WidgetKit swaps to it (dropping the ended
        // event) at that time with no networking and no refresh-budget cost.
        var references = [now]
        if let cache {
            references += AgendaPagination.upcomingEndTimes(
                after: now, before: tomorrow, cache: cache,
                calendarIds: ids, showDeclined: showDeclined
            )
        }
        let entries = references.map {
            AgendaEntryBuilder.live(calendarIds: ids, showDeclined: showDeclined,
                                    variant: variant, reference: $0, cache: cache)
        }

        return Timeline(entries: entries, policy: .after(tomorrow))
    }
}
