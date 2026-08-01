import AppIntents
import CalCore

/// Per-widget configuration: which calendars this instance shows. Backed by the catalog of every
/// signed-in account's calendars, so one widget can mix calendars from several accounts and each
/// placed widget filters the shared cache to its own set.
///
/// An empty selection is treated as "not yet configured" — the widget prompts the user to pick
/// calendars via Edit Widget rather than guessing. So is a selection that no longer parses, which
/// is what a widget configured before multi-account has: its stored ids name no account, and
/// resolving them against whichever account happens to own a matching calendarId would silently
/// show a different calendar than the one that was picked.
///
/// Uses a plain `[String]` parameter with a `DynamicOptionsProvider` rather than an `AppEntity`:
/// entity-array selections did not survive round-tripping through the widget's saved
/// configuration (they resolved to an empty array at render even though the picker saved them),
/// whereas raw string options persist directly with no entity-rehydration step to fail. The
/// values are `CalendarRef.encoded`, so they are still raw strings and that property holds.
///
/// Lives in `Shared/` rather than at the extension root because the app needs it too: deciding
/// which calendars to fetch means reading every placed widget's configuration — see `WidgetDemand`.
struct SelectCalendarsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Calendars"
    static var description = IntentDescription("Choose which calendars this widget shows.")

    @Parameter(title: "Calendars", optionsProvider: CalendarOptionsProvider())
    var calendarIds: [String]?

    /// When off (default), events the user declined are hidden. When on, they're shown struck
    /// through in red.
    @Parameter(title: "Show declined events", default: false)
    var showDeclinedEvents: Bool

    /// The chosen calendars — empty when the user hasn't picked any yet, and also empty when every
    /// stored value is unresolvable. `hasUnresolvableSelection` tells those apart.
    var selectedRefs: Set<CalendarRef> {
        Set((calendarIds ?? []).compactMap(CalendarRef.init(encoded:)))
    }

    /// True when this instance stores calendars that name no account — a widget configured before
    /// multi-account. Drives the same reconfigure prompt as an empty selection.
    var hasUnresolvableSelection: Bool {
        (calendarIds ?? []).contains { CalendarRef(encoded: $0) == nil }
    }
}

/// Supplies the calendar options from the catalog (every signed-in account's calendars), one
/// section per account so the same calendar name under two accounts stays distinguishable.
///
/// Reads the catalog, not the events cache: with demand-driven fetching nothing is fetched until
/// something is picked, so offering only what's already cached would leave the picker empty on a
/// fresh install and no calendar could ever be chosen.
struct CalendarOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> ItemCollection<String> {
        guard let catalog = CatalogStore(appGroupIdentifier: AppConfig.appGroupID)?.read() else {
            return ItemCollection(sections: [])
        }
        let sections = catalog.accountEmails.map { email in
            let sorted = catalog.sources(for: email)
                .sorted { $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending }
            return ItemSection<String>(
                LocalizedStringResource(stringLiteral: email),
                items: sorted.map { IntentItem($0.ref.encoded, title: "\($0.summary)") }
            )
        }
        return ItemCollection(sections: sections)
    }
}
