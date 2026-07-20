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
        let newOffset = store.twoWeekPageOffset + direction
        store.twoWeekPageOffset = newOffset

        var cal = Calendar.current
        cal.firstWeekday = 1
        let window = DateWindow(referenceDate: Date(), pageOffset: newOffset, weekCount: 2, calendar: cal)
        let alreadyCached = EventCache(appGroupIdentifier: AppConfig.appGroupID)?
            .read()?.covers(start: window.startDate, end: window.endExclusive) ?? false

        // Show the loading spinner only when we actually need to fetch this range.
        if !alreadyCached { store.beginSync() }
        // Page offset + spinner are grid-only state, so this one is a grid-only reload.
        WidgetReloader.reload(kind: AppConfig.twoWeekWidgetKind) // instant window change (+ spinner)

        if !alreadyCached {
            await SyncCoordinator.fetchWindowIfNeeded(pageOffset: newOffset, weekCount: 2, calendar: cal)
            store.endSync()
            WidgetReloader.reloadAll() // the fetch widened the cache — every widget re-reads it
        }
        return .result()
    }
}
