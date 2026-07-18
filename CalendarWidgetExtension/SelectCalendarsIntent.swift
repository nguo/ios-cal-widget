import AppIntents
import CalCore

/// Per-widget configuration: which calendars this instance shows. Backed by the shared cache's
/// superset of available calendars, so each placed widget filters the same cache to its own set.
/// An empty selection is treated as "not yet configured" — the widget prompts the user to pick
/// calendars via Edit Widget rather than guessing.
///
/// Uses a plain `[String]` (calendar-id) parameter with a `DynamicOptionsProvider` rather than an
/// `AppEntity`: entity-array selections did not survive round-tripping through the widget's saved
/// configuration (they resolved to an empty array at render even though the picker saved them),
/// whereas raw string options persist directly with no entity-rehydration step to fail.
struct SelectCalendarsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Calendars"
    static var description = IntentDescription("Choose which calendars this widget shows.")

    @Parameter(title: "Calendars", optionsProvider: CalendarOptionsProvider())
    var calendarIds: [String]?

    /// When off (default), events the user declined are hidden. When on, they're shown struck
    /// through in red.
    @Parameter(title: "Show declined events", default: false)
    var showDeclinedEvents: Bool

    /// The chosen calendar ids — empty when the user hasn't picked any yet.
    var selectedCalendarIds: Set<String> {
        Set(calendarIds ?? [])
    }
}

/// Supplies the calendar options (id value + calendar name as the label) from the shared cache
/// (the superset written by every sync), so the picker always matches what's actually synced.
struct CalendarOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> ItemCollection<String> {
        let sources = EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read()?.sources ?? []
        let sorted = sources.sorted { $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending }
        return ItemCollection(sections: [
            ItemSection(items: sorted.map { IntentItem($0.id, title: "\($0.summary)") })
        ])
    }
}
