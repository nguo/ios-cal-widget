import AppIntents
import CalCore

/// Resets pagination to the window containing today.
struct GoToTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Go to Today"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        guard let store = AppGroupStore(suiteName: AppConfig.appGroupID) else { return .result() }
        // Same in-flight guard as the chevrons: jumping the offset mid-fetch would land the
        // arriving page on a window the user has already navigated away from.
        guard !store.isSyncing else { return .result() }

        store.twoWeekPageOffset = 0
        // Grid-only: changes a page offset, not the cache.
        WidgetReloader.reload(kind: AppConfig.twoWeekWidgetKind)
        return .result()
    }
}
