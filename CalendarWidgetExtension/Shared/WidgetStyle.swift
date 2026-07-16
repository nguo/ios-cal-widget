import SwiftUI

/// Shared visual constants for the widget.
enum WidgetStyle {
    /// Sunday-only accent color (also used by the today glyph).
    static let accent = Color(red: 0.29, green: 0.53, blue: 0.91) // ~#4A87E8 blue
    /// Dim dark-blue fill behind today's date pill — reads as "today" without competing
    /// with the calendar event colors below it.
    static let todayPillBackground = Color(red: 0.11, green: 0.20, blue: 0.33) // ~#1C3355

    // Row geometry shared between WeekRowView (bar offsets) and ColumnView (reserved space).
    static let dateHeight: CGFloat = 14
    static let laneHeight: CGFloat = 12   // all-day bar lane
    static let timedRowHeight: CGFloat = 11

    // Agenda widget row geometry. Shared between AgendaGroupView (rendering) and
    // AgendaEntryBuilder (the fit calculation that decides how many events a page holds), so
    // they MUST stay in sync — the builder assumes rows render at exactly these heights.
    static let agendaDayHeaderHeight: CGFloat = 18
    static let agendaAllDayRowHeight: CGFloat = 16
    static let agendaTimedRowHeight: CGFloat = 30
    /// Height available for day-groups below the today-anchor row (TODAY + date + divider).
    /// Approximate (a widget can't measure before layout) — tune conservatively on a real
    /// small widget so nothing clips. Lowered from 112 to make room for the anchor+divider.
    static let agendaPageBudget: CGFloat = 96
}

extension View {
    /// Renders this view in a leading overlay over a flexible-width, fixed-height box, so its
    /// natural width can't widen the parent (keeps grid columns even) and overflow is
    /// hard-clipped with no ellipsis. Use for dense single-line grid rows.
    ///
    /// NOTE: this is the one place the "overlay + clip" trick lives — reuse it for any new
    /// clipped grid row so the width-propagation trap (fixedSize text growing the column)
    /// can't be reintroduced. (The all-day bar in WeekRowView uses the same principle over a
    /// shaped background.)
    func clippedGridRow(height: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: .leading) { self }
            .clipped()
    }
}
