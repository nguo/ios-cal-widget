import WidgetKit
import Foundation
import CalCore

/// One page of the agenda: the day-groups to render (each a day header + that day's events on
/// this page), plus whether earlier/later pages exist. Built from a forward-ordered event list,
/// so paging moves by whole events (a day can span page boundaries).
///
/// The WidgetKit-flavored wrapper only. The page math that produces `groups` — and
/// `AgendaDayGroup` itself — lives in `AgendaPagination` (CalCore), where it is unit-tested
/// off-device.
struct AgendaEntry: TimelineEntry {
    let date: Date
    /// The day-groups shown on the current page, in order. Empty when there's nothing to show.
    let groups: [AgendaDayGroup]
    /// Whether an earlier page exists (event offset > 0) — drives the up button.
    let canPageBack: Bool
    /// Whether a later page exists — drives the down button, hiding it at the last event.
    let canPageForward: Bool
    /// Index of this page's first event in the ordered list — the page's identity.
    ///
    /// Used as a SwiftUI `.id` so paging *replaces* the rows instead of matching them
    /// position-by-position against the previous page and animating each one to its new spot
    /// (`CalendarGridView` keys off `window.pageOffset` for the same reason).
    var pageStart: Int = 0
    /// Cache generation time; nil means never synced (drives the sign-in prompt).
    let lastSyncedAt: Date?
    /// This instance's calendar selection (nil ⇒ all). Carried so the paging button can hand it
    /// to `AgendaPageIntent`, keeping its boundary math aligned with the filtered event list.
    let calendarIds: Set<String>?
    /// This instance's "show declined" setting. Carried for the same reason as `calendarIds`:
    /// the paging button must compute boundaries over the same visible set.
    var showDeclined: Bool = false
    /// True when the widget has no calendars picked yet — drives the "Edit Widget to choose
    /// calendars" prompt instead of an empty agenda.
    var needsConfiguration: Bool = false
}
