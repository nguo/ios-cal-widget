import AppIntents
import Foundation
import CalCore

/// Pagination intent: shifts the shared page offset by one window (±1), reloads immediately
/// (instant window change), then auto-fetches that range if it isn't cached yet — so paging
/// into unfetched weeks fills in rather than showing empty.
struct ShiftWindowIntent: AppIntent {
    static var title: LocalizedStringResource = "Shift Calendar Window"
    static var isDiscoverable: Bool = false // widget-internal, not surfaced to Siri/Shortcuts

    /// +1 = forward (next window), -1 = backward (previous window).
    @Parameter(title: "Direction")
    var direction: Int

    init() {}
    init(direction: Int) { self.direction = direction }

    func perform() async throws -> some IntentResult {
        guard let store = AppGroupStore(suiteName: AppConfig.appGroupID) else { return .result() }
        // Ignore taps while a page is still loading. `MonthHeaderView` also dims the chevrons,
        // but that alone can't hold the line: the disabled state only reaches the user once
        // WidgetKit delivers the reloaded timeline, and taps landing before then would each
        // advance the offset — three quick taps skipped six weeks ahead of the fetch.
        guard !store.isSyncing else { return .result() }

        let newOffset = store.twoWeekPageOffset + direction
        let cal = Calendar.calWidget
        let window = DateWindow(referenceDate: Date(), pageOffset: newOffset, weekCount: AppConfig.gridWeekCount, calendar: cal)
        let alreadyCached = EventCache(appGroupIdentifier: AppConfig.appGroupID)?
            .read()?.covers(start: window.startDate, end: window.endExclusive) ?? false

        // Claim the in-flight flag *before* publishing the new offset, so a second tap arriving
        // in between is rejected rather than paging again. Re-checked here via `claimSync` rather
        // than trusting the guard above, since the cache read between them is a window in which
        // another process could have started syncing. A cached range needs no flag — there's
        // nothing to wait for, and flagging it would flicker the controls disabled for one frame
        // on an instant page turn.
        if !alreadyCached, !store.claimSync() { return .result() }
        store.twoWeekPageOffset = newOffset
        // Page offset + spinner are grid-only state, so this one is a grid-only reload.
        WidgetReloader.reload(kind: AppConfig.twoWeekWidgetKind) // instant window change (+ spinner)

        if !alreadyCached {
            await SyncCoordinator.fetchWindowIfNeeded(pageOffset: newOffset, weekCount: AppConfig.gridWeekCount, calendar: cal)
            store.endSync()
            WidgetReloader.reloadAll() // the fetch widened the cache — every widget re-reads it
        }
        return .result()
    }
}
