import WidgetKit
import SwiftUI
import CalCore

/// The two-week widget: `AppConfig.gridWeekCount` weeks in the `.systemMedium` family,
/// delegating rendering to `CalendarGridView`. The week count comes from `AppConfig` because the
/// paging intents and the sync range need the same number and can't be handed it per instance —
/// see that constant for what a differently-sized grid widget would actually require.
struct TwoWeekWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppConfig.twoWeekWidgetKind,
            intent: SelectCalendarsIntent.self,
            provider: CalendarTimelineProvider(weekCount: AppConfig.gridWeekCount)
        ) { entry in
            CalendarGridView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Two Weeks")
        .description("Two weeks of your Google Calendars.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled() // we manage our own (smaller) padding for wider cells
    }
}

#Preview(as: .systemMedium) {
    TwoWeekWidget()
} timeline: {
    WidgetFixtures.entry()
    WidgetFixtures.entry(pageOffset: 1)
}
