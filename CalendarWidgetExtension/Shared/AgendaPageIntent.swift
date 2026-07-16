import AppIntents
import WidgetKit
import CalCore

/// Agenda pagination: moves the visible window by one page via the deterministic page
/// boundaries (variable size — a page holds as many events as fit its height). Clamped so it
/// never pages before the first event or past the last (no blank pages): the down button is
/// always shown but is a no-op on the last page. No fetching — the agenda reads within the
/// cached horizon, which the canonical sync keeps fresh.
struct AgendaPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Page Agenda"
    static var isDiscoverable: Bool = false // widget-internal, not surfaced to Siri/Shortcuts

    /// +1 = forward (later events), -1 = backward (earlier events).
    @Parameter(title: "Direction")
    var direction: Int

    init() {}
    init(direction: Int) { self.direction = direction }

    func perform() async throws -> some IntentResult {
        guard let store = AppGroupStore(suiteName: AppConfig.appGroupID) else { return .result() }
        var cal = Calendar.current
        cal.firstWeekday = 1

        let ordered = EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read()
            .map { AgendaEntryBuilder.orderedEvents(reference: Date(), calendar: cal, cache: $0) } ?? []
        let bounds = AgendaEntryBuilder.boundaries(ordered)

        // Current page index (largest boundary ≤ the stored offset), then step one page.
        let current = bounds.lastIndex(where: { $0 <= store.agendaEventOffset }) ?? 0
        let next = min(max(current + direction, 0), bounds.count - 1)
        store.agendaEventOffset = bounds[next]
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.agendaWidgetKind)
        return .result()
    }
}

/// Jumps the agenda back to its first page (the window starting at today's first event).
/// Backs the tappable date anchor. Offset 0 always snaps to the first boundary in `live`.
struct AgendaGoToStartIntent: AppIntent {
    static var title: LocalizedStringResource = "Agenda First Page"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        AppGroupStore(suiteName: AppConfig.appGroupID)?.agendaEventOffset = 0
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.agendaWidgetKind)
        return .result()
    }
}
