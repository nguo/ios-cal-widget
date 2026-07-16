import SwiftUI
import CalCore

/// One day: the date number, then up to 4 rows of events (all-day bars first, then timed
/// chips), applying `DayCellContent`'s "3 + smart 4th line" rule. Dense layout; overflow
/// text is hard-clipped (no ellipsis). Today is marked with a grey outline around the cell.
struct DayCellView: View {
    let day: Date
    let events: [CalendarEvent]
    let calendar: Calendar

    /// Sunday-only accent color.
    static let accent = Color(red: 0.29, green: 0.53, blue: 0.91) // ~#4A87E8 blue

    private var dayNumber: Int { calendar.component(.day, from: day) }
    private var isToday: Bool { calendar.isDateInToday(day) }
    private var isSunday: Bool { calendar.component(.weekday, from: day) == 1 }

    private var content: DayCellContent { DayCellContent(events: events, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(dayNumber)")
                .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isSunday ? Self.accent : .white)
            ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(1)
        .clipped() // short cells can't hold all 4 rows — clip overflow rather than spill
        .contentShape(Rectangle()) // make the WHOLE cell tappable (incl. empty area) for the Link
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.white.opacity(isToday ? 0.5 : 0), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func rowView(_ row: DayCellContent.Row) -> some View {
        switch row {
        case let .event(event) where event.isAllDay:
            // All-day: darkened background bar behind white text.
            clippedRow(background: Color(hex: event.colorHex, brightness: 0.55)) {
                text(EventTextFormatter.line(for: event, calendar: calendar), color: .white)
                    .padding(.leading, 2)
            }
        case let .event(event):
            // Timed: colored left line, no background behind the text.
            clippedRow(background: .clear) {
                HStack(spacing: 3) {
                    Capsule().fill(Color(hex: event.colorHex)).frame(width: 2, height: 8)
                    text(EventTextFormatter.line(for: event, calendar: calendar), color: .white)
                }
                .padding(.leading, 1)
            }
        case let .moreCount(n):
            clippedRow(background: .clear) {
                text("+\(n) more", color: Color.white.opacity(0.5)).padding(.leading, 2)
            }
        }
    }

    private func text(_ string: String, color: Color) -> some View {
        Text(string)
            .font(.system(size: 8, weight: .medium))
            .lineLimit(1)
            .fixedSize() // render full text; overlay width doesn't affect the cell
            .foregroundStyle(color)
    }

    /// A single fixed-height row filling the (fixed 1/7) cell width. `content` lives in a
    /// leading overlay so its natural width can't widen the cell; overflow is hard-clipped
    /// (no ellipsis) by the rounded bounds.
    private func clippedRow<Content: View>(background: Color, @ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(background)
            .frame(maxWidth: .infinity)
            .frame(height: 11)
            .overlay(alignment: .leading, content: content)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}
