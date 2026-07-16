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
            dayHeader
                .frame(height: WidgetStyle.agendaDayHeaderHeight, alignment: .leading)
            ForEach(group.events) { event in
                eventRow(event)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle()) // whole group tappable for the Link
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

    /// Timed: two lines (name, then time range) beside a color bar spanning both.
    private func timedRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color(hex: event.colorHex))
                .frame(width: 3)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 1) {
                clippedLine(event.title, size: 12, weight: .medium, color: .white, height: 16)
                clippedLine(EventTextFormatter.timeRange(for: event, calendar: calendar),
                            size: 10, weight: .regular, color: Color.white.opacity(0.6), height: 12)
            }
        }
        .frame(height: WidgetStyle.agendaTimedRowHeight, alignment: .leading)
    }

    /// All-day: one line (name) on a darkened color background bar, like the grid.
    private func allDayRow(_ event: CalendarEvent) -> some View {
        Color(hex: event.colorHex, brightness: 0.55)
            .frame(maxWidth: .infinity)
            .frame(height: WidgetStyle.agendaAllDayRowHeight - 2)
            .overlay(alignment: .leading) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()          // full title; overlay width can't widen the bar
                    .foregroundStyle(.white)
                    .padding(.leading, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .frame(height: WidgetStyle.agendaAllDayRowHeight, alignment: .leading)
    }

    /// Single line, truncated by hard clipping (no ellipsis). Uses `clippedGridRow`'s overlay
    /// trick so the text's natural width can't widen the row (the `.fixedSize().frame(maxWidth:)`
    /// approach propagates that width and stretches the whole widget — the bug this avoids).
    private func clippedLine(_ string: String, size: CGFloat, weight: Font.Weight, color: Color, height: CGFloat) -> some View {
        Text(string)
            .font(.system(size: size, weight: weight))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .clippedGridRow(height: height)
    }
}
