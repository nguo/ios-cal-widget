import SwiftUI
import CalCore

/// Shared "E MMM d" day formatting (e.g. "Thu Jul 16"), used by both the header anchor and
/// the day-group headers so they stay identical.
enum AgendaDateFormat {
    static func header(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.dateFormat = "E MMM d"
        return f.string(from: date)
    }
}

/// One day-group on an agenda page: a day header ("Jul 18", or "Jul 18 (cont)" when the day's
/// events spilled from the previous page), then that day's events on this page. All events are
/// shown — the agenda never truncates with "+N more".
struct AgendaGroupView: View {
    let group: AgendaDayGroup
    let calendar: Calendar
    /// Today, for the "in N days" relative suffix and the today pill.
    let referenceDate: Date
    /// False in a non-widget host (e.g. an in-app preview) where the intent buttons don't apply;
    /// rows render as plain, non-tappable content there.
    var interactive: Bool = true

    private var isToday: Bool { calendar.isDateInToday(group.day) }

    private var headerText: String {
        let base = AgendaDateFormat.header(group.day, calendar: calendar)
        return group.isContinuation ? "\(base) (cont)" : base
    }

    /// Faint "tomorrow" / "in N days" suffix positioning the day relative to today. Nil for
    /// today (the pill says so) and for continuation headers (the day already appeared).
    private var relativeLabel: String? {
        guard !group.isContinuation else { return nil }
        let from = calendar.startOfDay(for: referenceDate)
        let to = calendar.startOfDay(for: group.day)
        guard let days = calendar.dateComponents([.day], from: from, to: to).day else { return nil }
        switch days {
        case ...0: return nil
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }

    var body: some View {
        // spacing 0: row heights (WidgetStyle) already include breathing room and the pagination
        // fit math assumes no inter-row gaps.
        VStack(alignment: .leading, spacing: 0) {
            // Day header opens that day; each event opens its own detail view. Small widgets ignore
            // `Link`, so taps route through OpenDeepLinkIntent -> the app -> Google Calendar.
            deepLinkRow(url: DeepLinkBuilder.dayURL(for: group.day, calendar: calendar)) {
                dayHeader
                    .frame(height: WidgetStyle.agendaDayHeaderHeight, alignment: .leading)
            }
            // Keyed by position, not by event: `CalendarEvent.id` is Google's event id, which is
            // NOT unique here — being invited on two connected accounts caches the same event once
            // per calendar, so both land in this group with the same id. Handing ForEach duplicate
            // ids renders the first row twice, showing the second event in the wrong color.
            ForEach(Array(group.events.enumerated()), id: \.offset) { _, event in
                deepLinkRow(url: eventDestination(event)) {
                    eventRow(event)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Wraps a row in a full-width tap target that deep-links to `url`. Interactive (widget) hosts
    /// use an intent button; non-interactive hosts render the plain content.
    @ViewBuilder
    private func deepLinkRow<Content: View>(url: URL, @ViewBuilder content: () -> Content) -> some View {
        let row = content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        if interactive {
            Button(intent: OpenDeepLinkIntent(url: url)) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    /// Deep link for an event row: the event itself via its Google `htmlLink`, falling back to the
    /// day when no event URL can be formed (see DeepLinkBuilder.eventURL).
    private func eventDestination(_ event: CalendarEvent) -> URL {
        (event.htmlLink.flatMap { DeepLinkBuilder.eventURL(htmlLink: $0) })
            ?? DeepLinkBuilder.dayURL(for: group.day, calendar: calendar)
    }

    @ViewBuilder
    private var dayHeader: some View {
        if isToday {
            // Dim dark-blue pill instead of bright-blue text, so "today" doesn't compete with
            // the calendar event colors below it.
            Text(headerText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(WidgetStyle.todayPillBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            HStack(spacing: 5) {
                Text(headerText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                if let relativeLabel {
                    Text("· \(relativeLabel)")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.32))
                }
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: CalendarEvent) -> some View {
        if event.isAllDay {
            allDayRow(event)
        } else {
            timedRow(event)
        }
    }

    /// Timed: two lines (name, then time range) beside a color bar spanning both. Declined events
    /// (shown only when the widget opts in) render in red with a strikethrough.
    private func timedRow(_ event: CalendarEvent) -> some View {
        let declined = event.isDeclined
        return HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(declined ? WidgetStyle.declinedColor : Color(hex: event.colorHex))
                .frame(width: 3)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 1) {
                ClippedLine(string: event.title, size: 12, weight: .medium,
                            color: declined ? WidgetStyle.declinedColor : .white, height: 16, strikethrough: declined)
                ClippedLine(string: EventTextFormatter.timeRange(for: event, calendar: calendar),
                            size: 10, weight: .regular,
                            color: declined ? WidgetStyle.declinedColor.opacity(0.7) : Color.white.opacity(0.6),
                            height: 12, strikethrough: declined)
            }
        }
        .frame(height: WidgetStyle.agendaTimedRowHeight, alignment: .leading)
    }

    /// All-day: one line (name) on a darkened color background bar, like the grid. Declined events
    /// dim the bar and render the title in red with a strikethrough.
    private func allDayRow(_ event: CalendarEvent) -> some View {
        let declined = event.isDeclined
        return Color(hex: event.colorHex, brightness: declined ? 0.28 : 0.55)
            .frame(maxWidth: .infinity)
            .frame(height: WidgetStyle.agendaAllDayRowHeight - 2)
            .overlay(alignment: .leading) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()          // full title; overlay width can't widen the bar
                    .strikethrough(declined)
                    .foregroundStyle(declined ? WidgetStyle.declinedColor : .white)
                    .padding(.leading, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .frame(height: WidgetStyle.agendaAllDayRowHeight, alignment: .leading)
    }

}
