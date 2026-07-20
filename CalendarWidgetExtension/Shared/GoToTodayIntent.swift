import AppIntents
import CalCore

/// Resets pagination to the window containing today.
struct GoToTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Go to Today"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        AppGroupStore(suiteName: AppConfig.appGroupID)?.twoWeekPageOffset = 0
        // Grid-only: changes a page offset, not the cache.
        WidgetReloader.reload(kind: AppConfig.twoWeekWidgetKind)
        return .result()
    }
}
