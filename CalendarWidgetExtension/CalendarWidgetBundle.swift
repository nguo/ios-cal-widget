import WidgetKit
import SwiftUI

/// Entry point for the widget extension. Lists every widget in the bundle — the two-week grid
/// and the small and medium scrolling agendas; a future one-week/three-week widget would be
/// added here.
@main
struct CalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        TwoWeekWidget()
        AgendaWidget()
        AgendaMediumWidget()
    }
}
