import Foundation
import CalCore

/// Assembles an `AgendaEntry` from shared App Group state: read the cache, read this variant's
/// stored page offset, hand both to `AgendaPagination`, and wrap the result for WidgetKit.
///
/// The page math itself now lives in `AgendaPagination` (CalCore), where it is unit-tested.
/// What remains here is the part that can't move: touching `AppGroupStore` / `EventCache` and
/// producing a `TimelineEntry`. Does no networking — reads only the cache.
enum AgendaEntryBuilder {

    /// Builds an entry from the shared cache, scoped to this widget instance's `calendarIds`
    /// (nil ⇒ show every calendar). `variant` selects which widget's stored page offset and page
    /// sizing to use. `offsetOverride` lets previews page independently of the stored offset.
    ///
    /// `cache` may be supplied by a caller that already read it: the timeline provider builds
    /// several entries per reload, and re-reading and re-decoding the whole file for each one is
    /// pure waste inside a memory-capped extension.
    static func live(
        calendarIds: Set<String>? = nil,
        showDeclined: Bool = false,
        variant: AgendaVariant = .small,
        reference: Date = Date(),
        offsetOverride: Int? = nil,
        cache preloaded: EventCacheData? = nil
    ) -> AgendaEntry {
        let cal = Calendar.calWidget
        let store = AppGroupStore(suiteName: AppConfig.appGroupID)
        let cache = preloaded ?? EventCache(appGroupIdentifier: AppConfig.appGroupID)?.read()
        let needsConfiguration = EventCacheData.needsConfiguration(calendarIds: calendarIds, cache: cache)

        guard let cache, !needsConfiguration else {
            return AgendaEntry(
                date: reference, groups: [], canPageBack: false, canPageForward: false,
                lastSyncedAt: cache?.generatedAt, calendarIds: calendarIds,
                showDeclined: showDeclined, needsConfiguration: needsConfiguration
            )
        }

        let ordered = AgendaPagination.orderedEvents(
            reference: reference, calendar: cal, cache: cache,
            calendarIds: calendarIds, showDeclined: showDeclined
        )
        let sizing = variant.pageSizing
        let stored = offsetOverride ?? store.map { variant.eventOffset(in: $0) } ?? 0
        // Snap to the nearest page boundary <= the stored offset (it may drift after a re-sync).
        let bounds = AgendaPagination.boundaries(ordered, sizing: sizing)
        let start = AgendaPagination.pageStart(for: stored, in: bounds)

        return AgendaEntry(
            date: reference,
            groups: AgendaPagination.groups(from: ordered, offset: start, sizing: sizing),
            canPageBack: start > 0,
            canPageForward: start < (bounds.last ?? 0), // a later page boundary exists
            pageStart: start,
            lastSyncedAt: cache.generatedAt,
            calendarIds: calendarIds,
            showDeclined: showDeclined,
            needsConfiguration: false
        )
    }
}
