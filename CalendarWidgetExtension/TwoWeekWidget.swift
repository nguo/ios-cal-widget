import WidgetKit
import SwiftUI
import CalCore

/// The two-week widget. This is the ONLY week-count-specific declaration: it fixes
/// `weekCount: 2` and the `.systemLarge` family, then delegates rendering to the generic
/// `CalendarGridView`. A future OneWeekWidget/ThreeWeekWidget would mirror this file.
struct TwoWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConfig.twoWeekWidgetKind, provider: CalendarTimelineProvider(weekCount: 2)) { entry in
            CalendarGridView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Two Weeks")
        .description("Two weeks of your Google Calendars.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled() // we manage our own (smaller) padding for wider cells
    }
}

#Preview(as: .systemLarge) {
    TwoWeekWidget()
} timeline: {
    WidgetFixtures.entry()
    WidgetFixtures.entry(pageOffset: 1)
}
