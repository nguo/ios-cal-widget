import WidgetKit
import SwiftUI
import CalCore

/// The medium scrolling-agenda widget: a paging rail, a date column, and filled event cards.
/// Same data and configuration as `AgendaWidget` — reusing `SelectCalendarsIntent` gives each
/// placed instance its own calendar selection and declined-events toggle, since WidgetKit keys a
/// configuration intent per widget instance. Paging state is separate from the small widget's
/// (see `AgendaVariant`).
struct AgendaMediumWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppConfig.agendaMediumWidgetKind,
            intent: SelectCalendarsIntent.self,
            provider: AgendaTimelineProvider(variant: .medium)
        ) { entry in
            AgendaMediumView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Agenda (Medium)")
        .description("A scrolling agenda of your upcoming days, with room for full event cards.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled() // we manage our own padding
    }
}

#Preview(as: .systemMedium) {
    AgendaMediumWidget()
} timeline: {
    WidgetFixtures.agendaEntry(variant: .medium)
    WidgetFixtures.agendaEntry(eventOffset: 3, variant: .medium)
}
