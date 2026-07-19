import Foundation
import CoreGraphics
import CalCore

/// Which agenda widget a piece of paging state belongs to. The two agenda widgets share all of
/// their data plumbing (cache, ordering, filtering) but differ in three ways that have to travel
/// together: the WidgetKit `kind` to reload, the App Group key holding the page offset, and how
/// many events one page holds. Bundling them here keeps the builder and the paging intents from
/// having to be handed three loosely-related values.
///
/// Raw-value backed because `AppIntent` parameters must be simple types — the paging intents carry
/// the variant across the process hop as a string.
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
        case .small: return .heightFit
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

/// How many events fit one agenda page.
enum AgendaPageSizing {
    /// The small widget: a greedy walk costing each row by its rendered height (all-day rows are
    /// shorter than timed, and each new day adds a header) against a height budget. Page capacity
    /// therefore varies with content.
    case heightFit
    /// The medium widget: uniform two-line cards with no per-day header in the event column, so a
    /// page is simply a constant number of events.
    case fixedCount(Int)

    /// How many events (starting at `start`) this sizing fits on one page. Always ≥ 1 so a lone
    /// oversized event still shows (it just clips).
    func eventsThatFit(_ ordered: [(day: Date, event: CalendarEvent)], from start: Int) -> Int {
        switch self {
        case .fixedCount(let n):
            return max(min(n, ordered.count - start), 1)
        case .heightFit:
            var used: CGFloat = 0
            var count = 0
            var lastDay: Date?
            var i = start
            while i < ordered.count {
                let (day, event) = ordered[i]
                var cost = event.isAllDay ? WidgetStyle.agendaAllDayRowHeight : WidgetStyle.agendaTimedRowHeight
                if day != lastDay { cost += WidgetStyle.agendaDayHeaderHeight }
                if count > 0 && used + cost > WidgetStyle.agendaPageBudget { break }
                used += cost
                lastDay = day
                count += 1
                i += 1
            }
            return max(count, 1)
        }
    }
}
