import AppIntents
import Foundation
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

    /// The requesting widget instance's calendar selection (empty ⇒ all). Kept so the page
    /// boundaries computed here match the filtered list the widget actually shows.
    @Parameter(title: "Calendars")
    var calendarIds: [String]

    /// The requesting instance's "show declined" setting — same reason: boundaries must be
    /// computed over the same visible set the widget renders.
    @Parameter(title: "Show declined", default: false)
    var showDeclined: Bool

    /// Which agenda widget is asking (`AgendaVariant` raw value). Selects the offset key to move,
    /// the page sizing to compute boundaries with, and the widget kind to reload — the two agenda
    /// widgets page independently.
    @Parameter(title: "Variant", default: "small")
    var variant: String

    init() {}
    init(direction: Int, calendarIds: Set<String>? = nil, showDeclined: Bool = false, variant: AgendaVariant = .small) {
        self.direction = direction
        self.calendarIds = calendarIds.map(Array.init) ?? []
        self.showDeclined = showDeclined
        self.variant = variant.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let store = AppGroupStore(suiteName: AppConfig.appGroupID) else { return .result() }
        let agenda = AgendaVariant(rawValue: variant) ?? .small
        var cal = Calendar.current
        cal.firstWeekday = 1

        let ids = calendarIds.isEmpty ? nil : Set(calendarIds)
        let ordered = EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read()
            .map { AgendaEntryBuilder.orderedEvents(reference: Date(), calendar: cal, cache: $0, calendarIds: ids, showDeclined: showDeclined) } ?? []
        let bounds = AgendaEntryBuilder.boundaries(ordered, sizing: agenda.pageSizing)

        // Current page index (largest boundary ≤ the stored offset), then step one page.
        let current = bounds.lastIndex(where: { $0 <= agenda.eventOffset(in: store) }) ?? 0
        let next = min(max(current + direction, 0), bounds.count - 1)
        agenda.setEventOffset(bounds[next], in: store)
        // This variant only: paging changes its offset, not the cache.
        WidgetReloader.reload(kind: agenda.widgetKind)
        return .result()
    }
}

/// Jumps the agenda back to its first page (the window starting at today's first event).
/// Backs the tappable date anchor. Offset 0 always snaps to the first boundary in `live`.
struct AgendaGoToStartIntent: AppIntent {
    static var title: LocalizedStringResource = "Agenda First Page"
    static var isDiscoverable: Bool = false

    /// Which agenda widget is asking (`AgendaVariant` raw value).
    @Parameter(title: "Variant", default: "small")
    var variant: String

    init() {}
    init(variant: AgendaVariant = .small) { self.variant = variant.rawValue }

    func perform() async throws -> some IntentResult {
        let agenda = AgendaVariant(rawValue: variant) ?? .small
        if let store = AppGroupStore(suiteName: AppConfig.appGroupID) {
            agenda.setEventOffset(0, in: store)
        }
        WidgetReloader.reload(kind: agenda.widgetKind)
        return .result()
    }
}

/// Opens a Google Calendar deep link from the agenda widget. A `systemSmall` widget ignores
/// SwiftUI `Link`, so each tappable row is a `Button(intent:)` running this instead: it stashes the
/// target URL in the App Group and (via `openAppWhenRun`) opens the app, which forwards to Google
/// Calendar and clears the link (see CalWidgetApp.RootView).
struct OpenDeepLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Calendar Link"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true

    @Parameter(title: "URL")
    var url: String

    init() {}
    init(url: URL) { self.url = url.absoluteString }

    func perform() async throws -> some IntentResult {
        AppGroupStore(suiteName: AppConfig.appGroupID)?.pendingDeepLink = url
        return .result()
    }
}
