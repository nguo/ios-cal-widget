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

    /// The requesting widget instance's calendar selection as encoded `CalendarRef`s (empty ⇒
    /// all). Kept so the page boundaries computed here match the filtered list the widget shows.
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
    init(direction: Int, refs: Set<CalendarRef>? = nil, showDeclined: Bool = false, variant: AgendaVariant = .small) {
        self.direction = direction
        self.calendarIds = refs.map { $0.map(\.encoded) } ?? []
        self.showDeclined = showDeclined
        self.variant = variant.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let store = AppGroupStore(suiteName: AppConfig.appGroupID) else { return .result() }
        let agenda = AgendaVariant(rawValue: variant) ?? .small

        let refs = calendarIds.isEmpty ? nil : Set(calendarIds.compactMap(CalendarRef.init(encoded:)))
        let ordered = EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read()
            .map { AgendaPagination.orderedEvents(reference: Date(), calendar: .calWidget, cache: $0, refs: refs, showDeclined: showDeclined) } ?? []
        let bounds = AgendaPagination.boundaries(ordered, sizing: agenda.pageSizing)

        // Same boundary walk the builder uses, so a tap always lands where the widget renders.
        let stepped = AgendaPagination.steppedOffset(
            from: agenda.eventOffset(in: store), direction: direction, bounds: bounds
        )
        agenda.setEventOffset(stepped, in: store)
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
