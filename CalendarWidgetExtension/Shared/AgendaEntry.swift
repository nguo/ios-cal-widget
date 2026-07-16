import WidgetKit
import Foundation
import CalCore

/// One page of the agenda: the day-groups to render (each a day header + that day's events on
/// this page), plus whether an earlier page exists. Built from a forward-ordered event list, so
/// paging moves by whole events (a day can span page boundaries).
struct AgendaEntry: TimelineEntry {
    let date: Date
    /// The day-groups shown on the current page, in order. Empty when there's nothing to show.
    let groups: [AgendaDayGroup]
    /// Whether an earlier page exists (event offset > 0) — drives the up button. The down button
    /// is always shown; its bound is enforced by clamping the offset, not a flag.
    let canPageBack: Bool
    /// Cache generation time; nil means never synced (drives the sign-in prompt).
    let lastSyncedAt: Date?
}

/// A day's events on a single agenda page. `isContinuation` is true when this day's header
/// already appeared on the previous page (the day's events spilled across the page boundary),
/// rendered as "Jul 18 (cont)".
struct AgendaDayGroup: Identifiable {
    let day: Date
    let isContinuation: Bool
    let events: [CalendarEvent]
    var id: Date { day }
}
