import SwiftUI
import WidgetKit
import CalCore

/// The small agenda widget: an "AGENDA" header with up/down paging buttons (top-right), then the
/// current page's day-groups. Within a group, the day header opens the Google Calendar app to that
/// day and each event row opens that event's detail view (see AgendaGroupView).
/// The up button hides on the first page; the down button hides on the last page. Reads an
/// `AgendaEntry`; no networking here.
struct AgendaView: View {
    let entry: AgendaEntry
    /// False in a non-widget host (e.g. an in-app preview) where live intent buttons don't apply.
    var interactive: Bool = true

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if entry.needsConfiguration {
                configMessage
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if entry.groups.isEmpty {
                emptyMessage
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                // spacing 0 so rendered group heights match AgendaEntryBuilder's fit math.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entry.groups) { group in
                        // Per-row deep links inside the group: the day header opens that day, each
                        // event opens its own detail view (routed through the app; see AgendaGroupView).
                        AgendaGroupView(group: group, calendar: calendar,
                                        referenceDate: entry.date, interactive: interactive)
                    }
                }
                // Claim all space below the header and hard-clip our own overflow, so a fuller
                // page can't grow the VStack past the widget and get vertically centered — which
                // was nudging the anchor up. agendaPageBudget targets this region; clip is the net.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transaction { $0.animation = nil }
        .contentTransition(.identity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Centered anchor (tap → first page) with paging chevrons pinned to the corners
            // (up top-left, down top-right) — a symmetric header that reads apart from the day
            // rows below.
            ZStack { anchorControl }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    if interactive && entry.canPageBack { pageButton(-1, "chevron.up") }
                }
                .overlay(alignment: .topTrailing) {
                    if interactive && entry.canPageForward { pageButton(1, "chevron.down") }
                }
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
        .transaction { $0.animation = nil }
        .contentTransition(.identity)
    }

    /// The anchor, tappable to jump back to the first page in the live widget (plain elsewhere).
    @ViewBuilder
    private var anchorControl: some View {
        if interactive {
            Button(intent: AgendaGoToStartIntent()) { todayAnchor }
                .buttonStyle(.plain)
        } else {
            todayAnchor
        }
    }

    /// Fixed reference point, always shown regardless of which page is scrolled into view (so
    /// events below read as relative to now). Stacked "TODAY" over the date, centered, so it
    /// stays compact on a narrow small widget and the date never truncates.
    private var todayAnchor: some View {
        VStack(alignment: .center, spacing: 1) {
            Text("TODAY")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Color.white.opacity(0.42))
            Text(AgendaDateFormat.header(entry.date, calendar: calendar))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func pageButton(_ direction: Int, _ systemName: String) -> some View {
        Button(intent: AgendaPageIntent(direction: direction, calendarIds: entry.calendarIds, showDeclined: entry.showDeclined)) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var emptyMessage: some View {
        Text(entry.lastSyncedAt == nil ? "Open the app to sign in & sync" : "No upcoming events")
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.white.opacity(0.5))
    }

    /// Shown when the widget has no calendars picked yet (long-press → Edit Widget).
    private var configMessage: some View {
        Text("Edit Widget to choose calendars")
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.white.opacity(0.5))
    }
}
