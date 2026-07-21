import WidgetKit
import SwiftUI

/// Entry point for the widget extension. Lists every widget in the bundle — the two-week grid
/// and the small and medium paginating agendas; a future one-week/three-week widget would be
/// added here.
@main
struct CalendarWidgetBundle: WidgetBundle {
    /// Runs on the main thread at extension launch. Resolving the device metrics here keeps the
    /// background timeline providers from being the first to touch main-thread-only `UIScreen`.
    init() {
        WidgetStyle.primeDeviceMetrics()
    }

    var body: some Widget {
        TwoWeekWidget()
        AgendaWidget()
        AgendaMediumWidget()
    }
}
