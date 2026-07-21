import SwiftUI
import WidgetKit
import CalCore

/// The full widget: month header, weekday row, and a 2×7 (generally N×7) grid of day cells
/// that fills the (compact, `.systemMedium`) widget height. Each cell is a Link opening the
/// Google Calendar app to that day. Reads from a `CalendarTimelineEntry`; no networking here.
/// The stale/setup banner sits at the bottom, centered, only when shown.
struct CalendarGridView: View {
    let entry: CalendarTimelineEntry
    /// False in the in-app preview (its header glyphs are static — see MonthHeaderView).
    var interactive: Bool = true

    private var calendar: Calendar { .calWidget }

    private var weeks: [[Date]] {
        stride(from: 0, to: entry.window.days.count, by: 7).map {
            Array(entry.window.days[$0 ..< min($0 + 7, entry.window.days.count)])
        }
    }

    /// Today's day-of-month when the window is paged away from today; nil when on today.
    private var todayDayNumber: Int? {
        entry.window.pageOffset == 0 ? nil : calendar.component(.day, from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MonthHeaderView(monthLabel: entry.window.monthLabel(calendar: calendar),
                            isSyncing: entry.isSyncing,
                            todayDayNumber: todayDayNumber,
                            interactive: interactive)
                .padding(.horizontal, 4)
            WeekdayHeaderRow()

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                WeekRowView(
                    days: week,
                    layout: WeekLayout(days: week, eventsByDay: entry.eventsByDay, calendar: calendar, maxRowsPerCell: 4),
                    calendar: calendar
                )
                .frame(maxHeight: .infinity)
            }

            if entry.needsConfiguration {
                banner("Edit Widget to choose calendars")
            // Loading wins over the stale banner: telling the user to tap refresh *during* a
            // refresh is the state this replaced.
            } else if entry.isSyncing {
                banner("Loading…")
            } else if entry.cacheIsStale {
                banner(entry.lastSyncedAt == nil ? "Open the app to sign in & sync"
                                                 : "Tap refresh to load this range")
            }
        }
        .padding(6)
        // Break view identity per page so paging swaps the whole grid instead of matching
        // same-index all-day bars across snapshots and sliding them to their new columns.
        .id(entry.window.pageOffset)
        .transaction { $0.animation = nil }
    }

    /// The single status line at the bottom of the grid: loading, stale, or "pick calendars".
    ///
    /// Deliberately text, not a spinner. A widget is a static snapshot — WidgetKit never
    /// animates it — so the `ProgressView` this replaced could not spin, and rendered as an
    /// inert ring in a dark circle that tinting then flattened into a pale blob. Words say
    /// "loading" in every rendering mode and cost no space the banner wasn't already using.
    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(Color.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
