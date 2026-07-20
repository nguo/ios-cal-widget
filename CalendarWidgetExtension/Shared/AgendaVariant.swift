import Foundation
import CalCore

/// Which agenda widget a piece of paging state belongs to. The two agenda widgets share all of
/// their data plumbing (cache, ordering, filtering) but differ in three ways that have to travel
/// together: the WidgetKit `kind` to reload, the App Group key holding the page offset, and how
/// many events one page holds. Bundling them here keeps the builder and the paging intents from
/// having to be handed three loosely-related values.
///
/// This is also the seam where `WidgetStyle`'s measurements are handed to CalCore's
/// Foundation-only page math: the widget owns the numbers, `AgendaPagination` owns the algorithm.
///
/// Raw-value backed because `AppIntent` parameters must be simple types — the paging intents
/// carry the variant across the process hop as a string.
enum AgendaVariant: String {
    case small
    case medium

    /// The WidgetKit `kind` to reload after this variant's offset changes.
    var widgetKind: String {
        switch self {
        case .small: return AppConfig.agendaWidgetKind
        case .medium: return AppConfig.agendaMediumWidgetKind
        }
    }

    /// How this variant decides where its pages break.
    var pageSizing: AgendaPageSizing {
        switch self {
        case .small: return .heightFit(WidgetStyle.agendaMetrics)
        case .medium: return .fixedCount(WidgetStyle.agendaMediumRowsPerPage)
        }
    }

    func eventOffset(in store: AppGroupStore) -> Int {
        switch self {
        case .small: return store.agendaEventOffset
        case .medium: return store.agendaMediumEventOffset
        }
    }

    func setEventOffset(_ value: Int, in store: AppGroupStore) {
        switch self {
        case .small: store.agendaEventOffset = value
        case .medium: store.agendaMediumEventOffset = value
        }
    }
}
