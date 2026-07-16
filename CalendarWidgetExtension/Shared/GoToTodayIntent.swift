import AppIntents
import WidgetKit
import CalCore

/// Resets pagination to the window containing today.
struct GoToTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Go to Today"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        AppGroupStore(suiteName: AppConfig.appGroupID)?.twoWeekPageOffset = 0
        WidgetCenter.shared.reloadTimelines(ofKind: AppConfig.twoWeekWidgetKind)
        return .result()
    }
}
