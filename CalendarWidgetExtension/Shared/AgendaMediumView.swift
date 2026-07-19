import SwiftUI
import WidgetKit
import CalCore

/// The medium agenda widget: three columns — a slim paging rail, a date column, and full-width
/// event cards. Renders the same `AgendaEntry` the small `AgendaView` does, so all the data
/// plumbing (filtering, paging boundaries, continuation flags) is shared; only the layout differs.
///
/// Unlike the small widget, `systemMedium` can follow a SwiftUI `Link`, so rows deep-link straight
/// to Google Calendar instead of hopping through the app via `OpenDeepLinkIntent`.
struct AgendaMediumView: View {
    let entry: AgendaEntry
    /// False in a non-widget host (e.g. the in-app preview) where live intent buttons and links
    /// don't apply; rows render as plain, non-tappable content there.
    var interactive: Bool = true

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }

    /// One rendered row. `isGroupLead` drives the date column: only a group's first event carries
    /// the date, so the date lines up with the top of its first card and the rest sit blank.
    ///
    /// Identity is the row's position on the page, NOT the event: the same event id legitimately
    /// appears twice on one day when you're invited on two connected accounts (it's cached once per
    /// calendar). Keying on the event then hands `ForEach` duplicate ids, which renders the first
    /// row twice — including its date label.
    private struct Row: Identifiable {
        let id: Int
        let event: CalendarEvent
        let day: Date
        let isGroupLead: Bool
        let isContinuation: Bool
    }

    /// Flattens the day-groups into a single ordered row list so the date and event columns share
    /// one vertical rhythm (a nested per-group VStack would drift as soon as spacing changed).
    private var rows: [Row] {
        var result: [Row] = []
        for group in entry.groups {
            for (index, event) in group.events.enumerated() {
                result.append(Row(id: result.count, event: event, day: group.day,
                                  isGroupLead: index == 0, isContinuation: group.isContinuation))
            }
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            rail
            if entry.needsConfiguration {
                message("Edit Widget to choose calendars")
            } else if rows.isEmpty {
                message(entry.lastSyncedAt == nil ? "Open the app to sign in & sync" : "No upcoming events")
            } else {
                VStack(spacing: WidgetStyle.agendaMediumRowSpacing) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
                // Claim the space and hard-clip our own overflow, so a full page can't grow past
                // the widget and get vertically centered.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transaction { $0.animation = nil }
        .contentTransition(.identity)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.white.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Rail

    /// Paging controls pinned to the column's top, center, and bottom by overlay alignment rather
    /// than stacked, so the rail's geometry is identical on every page. All three are always
    /// present; the chevrons grey out at the ends of the range instead of disappearing.
    private var rail: some View {
        Color.clear
            .frame(width: WidgetStyle.agendaMediumRailWidth)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .top) {
                pageButton(-1, "chevron.up", enabled: entry.canPageBack)
            }
            .overlay(alignment: .center) {
                todayButton
            }
            .overlay(alignment: .bottom) {
                pageButton(1, "chevron.down", enabled: entry.canPageForward)
            }
    }

    /// A disabled control renders as plain (non-tappable) content rather than a disabled `Button`,
    /// so there's no intent wired up at all at the ends of the range.
    @ViewBuilder
    private func pageButton(_ direction: Int, _ systemName: String, enabled: Bool) -> some View {
        let glyph = railGlyph(
            Image(systemName: systemName).font(.system(size: 14, weight: .bold)),
            foreground: enabled ? .white : Color.white.opacity(0.25),
            background: Color.white.opacity(enabled ? 0.15 : 0.06)
        )
        if interactive && enabled {
            Button(intent: AgendaPageIntent(direction: direction, calendarIds: entry.calendarIds,
                                            showDeclined: entry.showDeclined, variant: .medium)) {
                glyph
            }
            .buttonStyle(.plain)
        } else {
            glyph
        }
    }

    /// Jumps back to the first page. Shows today's day-of-month rather than an arrow glyph, so it
    /// names the destination — the first page may well not start on today.
    @ViewBuilder
    private var todayButton: some View {
        let glyph = railGlyph(
            Text(String(calendar.component(.day, from: entry.date)))
                .font(.system(size: 13, weight: .medium)),
            foreground: .white,
            background: WidgetStyle.todayPillBackground
        )
        if interactive {
            Button(intent: AgendaGoToStartIntent(variant: .medium)) { glyph }
                .buttonStyle(.plain)
        } else {
            glyph
        }
    }

    private func railGlyph<Content: View>(_ content: Content, foreground: Color, background: Color) -> some View {
        content
            .foregroundStyle(foreground)
            .frame(width: WidgetStyle.agendaMediumRailButtonSize, height: WidgetStyle.agendaMediumRailButtonSize)
            .background(background, in: Circle())
    }

    // MARK: - Rows

    private func rowView(_ row: Row) -> some View {
        HStack(alignment: .top, spacing: 0) {
            dateCell(row)
                .frame(width: WidgetStyle.agendaMediumDateColumnWidth, alignment: .leading)
            linked(row) { card(row.event) }
        }
        .frame(height: WidgetStyle.agendaMediumRowHeight)
    }

    /// Stacked weekday-over-day-number, blank for every event after a group's first. A page that
    /// opens mid-day dims its leading date — the day already had its turn on the previous page.
    @ViewBuilder
    private func dateCell(_ row: Row) -> some View {
        if row.isGroupLead {
            // spacing 0 with explicitly-sized lines: the two labels must total exactly one row
            // height or the stack overflows its row and SwiftUI crops it top and bottom.
            VStack(alignment: .leading, spacing: 0) {
                Text(weekdayText(row.day))
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(height: WidgetStyle.agendaMediumWeekdayHeight, alignment: .top)
                Text(String(calendar.component(.day, from: row.day)))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(height: WidgetStyle.agendaMediumDayNumberHeight, alignment: .bottom)
            }
            .opacity(row.isContinuation ? 0.4 : 1)
        } else {
            Color.clear
        }
    }

    private func weekdayText(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.dateFormat = "E"
        return f.string(from: date).uppercased()
    }

    /// Wraps a card in a deep link to the event (falling back to its day). `systemMedium` follows
    /// `Link` directly, so no app hop is needed.
    @ViewBuilder
    private func linked<Content: View>(_ row: Row, @ViewBuilder content: () -> Content) -> some View {
        let body = content()
        if interactive {
            Link(destination: destination(row), label: { body })
        } else {
            body
        }
    }

    private func destination(_ row: Row) -> URL {
        (row.event.htmlLink.flatMap { DeepLinkBuilder.eventURL(htmlLink: $0) })
            ?? DeepLinkBuilder.dayURL(for: row.day, calendar: calendar)
    }

    /// Two lines on a filled card: title, then the time range — or the literal "All Day", which is
    /// the only thing distinguishing an all-day event here (both kinds get the same card).
    private func card(_ event: CalendarEvent) -> some View {
        let declined = event.isDeclined
        // Declined cards drop to a dim fill and flip to light text; dark-on-bright would be
        // illegible once the fill is darkened.
        let fill = Color(hex: event.colorHex, brightness: declined ? 0.28 : 1.0)
        let titleColor = declined ? Color.white.opacity(0.75) : Color(hex: event.colorHex, brightness: 0.22)
        let detailColor = declined ? Color.white.opacity(0.5) : Color(hex: event.colorHex, brightness: 0.42)
        let detail = event.isAllDay ? "All Day" : EventTextFormatter.timeRange(for: event, calendar: calendar)

        return VStack(alignment: .leading, spacing: 1) {
            clippedLine(event.title, size: 12.5, weight: .medium, color: titleColor, height: 15, strikethrough: declined)
            clippedLine(detail, size: 11, weight: .regular, color: detailColor, height: 13, strikethrough: declined)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    /// Single line, truncated by hard clipping (no ellipsis). Uses `clippedGridRow`'s overlay trick
    /// so the text's natural width can't widen the card.
    private func clippedLine(_ string: String, size: CGFloat, weight: Font.Weight, color: Color, height: CGFloat, strikethrough: Bool = false) -> some View {
        Text(string)
            .font(.system(size: size, weight: weight))
            .lineLimit(1)
            .fixedSize()
            .strikethrough(strikethrough)
            .foregroundStyle(color)
            .clippedGridRow(height: height)
    }
}
