import WidgetKit
import Foundation
import CalCore

/// Reads the pre-built cache + shared pagination offset and produces timeline entries, scoped to
/// this widget instance's calendar selection (`SelectCalendarsIntent`). Generic over `weekCount`
/// so a future one-week/three-week widget reuses it unchanged. Rendering itself reads only the
/// App Group cache; the sole network call is `CoverageRefresh`, when the reload lands on a window
/// the cache no longer covers.
struct CalendarTimelineProvider: AppIntentTimelineProvider {
    let weekCount: Int

    func placeholder(in context: Context) -> CalendarTimelineEntry {
        // Placeholder always uses sample data (real cache may not exist in the gallery).
        WidgetFixtures.entry()
    }

    func snapshot(for configuration: SelectCalendarsIntent, in context: Context) async -> CalendarTimelineEntry {
        // Gallery preview: sample data, since the real cache may be empty or absent.
        if context.isPreview { return WidgetFixtures.entry() }
        return CalendarEntryBuilder.live(weekCount: weekCount, calendarIds: configuration.selectedCalendarIds, showDeclined: configuration.showDeclinedEvents)
    }

    func timeline(for configuration: SelectCalendarsIntent, in context: Context) async -> Timeline<CalendarTimelineEntry> {
        let now = Date()
        let cal = Calendar.calWidget

        // The one place this provider may touch the network. At a week rollover the midnight
        // reload lands on a window the cache no longer covers; without this the grid shows the
        // stale banner until a background task the user can't see or trigger happens to run.
        let offset = AppGroupStore(suiteName: AppConfig.appGroupID)?.twoWeekPageOffset ?? 0
        let window = DateWindow(referenceDate: now, pageOffset: offset, weekCount: weekCount, calendar: cal)
        await CoverageRefresh.syncIfUncovered(start: window.startDate, end: window.endExclusive, calendar: cal, now: now)

        let entry = CalendarEntryBuilder.live(weekCount: weekCount, calendarIds: configuration.selectedCalendarIds, showDeclined: configuration.showDeclinedEvents)
        // Data reloads are pushed by syncs/intents; this fallback reload lands at the next
        // midnight so the "today" marker and the week anchor advance right at the day/week
        // boundary (offset-0 window re-derives from the new date).
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        return Timeline(entries: [entry], policy: .after(tomorrow))
    }
}
