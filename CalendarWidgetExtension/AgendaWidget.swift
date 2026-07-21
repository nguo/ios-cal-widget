import WidgetKit
import SwiftUI
import CalCore

/// The small paginating-agenda widget: a paged list of upcoming days. Delegates rendering to
/// `AgendaView`; paging is handled by `AgendaPageIntent` buttons inside the view.
struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppConfig.agendaWidgetKind,
            intent: SelectCalendarsIntent.self,
            provider: AgendaTimelineProvider()
        ) { entry in
            AgendaView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Agenda")
        .description("A paginating agenda of your upcoming days.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled() // we manage our own padding
    }
}

#Preview(as: .systemSmall) {
    AgendaWidget()
} timeline: {
    WidgetFixtures.agendaEntry()
    WidgetFixtures.agendaEntry(eventOffset: 3)
}
