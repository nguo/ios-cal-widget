import SwiftUI
import CalCore

/// One week (7 columns). All-day events render as **connected spanning bars** laid out by
/// `WeekLayout` and overlaid across columns; timed events + the date number stay per-column.
/// Each column is a `Link` (tap → Google Calendar's Schedule view starting on that day); the bars
/// sit above with hit testing disabled so taps fall through to the column.
struct WeekRowView: View {
    let days: [Date]
    let layout: WeekLayout
    let calendar: Calendar

    var body: some View {
        GeometryReader { geo in
            let colW = geo.size.width / 7
            ZStack(alignment: .topLeading) {
                // Layer A — per-column cells (date + timed), tappable.
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element) { col, day in
                        Link(destination: DeepLinkBuilder.scheduleURL(for: day, calendar: calendar)) {
                            ColumnView(day: day,
                                       timed: layout.timedByColumn[col],
                                       laneSpace: CGFloat(layout.lanesByColumn[col] ?? 0) * WidgetStyle.laneHeight,
                                       calendar: calendar)
                        }
                    }
                }
                // Layer B — spanning all-day bars (taps pass through to the columns).
                ForEach(Array(layout.allDaySegments.enumerated()), id: \.offset) { _, seg in
                    allDayBar(seg, colW: colW)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func allDayBar(_ seg: WeekLayout.AllDaySegment, colW: CGFloat) -> some View {
        let x = CGFloat(seg.startColumn) * colW + 0.5
        let width = CGFloat(seg.columnSpan) * colW - 1
        let y = WidgetStyle.dateHeight + CGFloat(seg.lane) * WidgetStyle.laneHeight
        let r: CGFloat = 2
        // Rounded on the real start/end, squared where it continues into an adjacent week.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: seg.continuesLeft ? 0 : r,
            bottomLeadingRadius: seg.continuesLeft ? 0 : r,
            bottomTrailingRadius: seg.continuesRight ? 0 : r,
            topTrailingRadius: seg.continuesRight ? 0 : r,
            style: .continuous
        )
        return shape
            .fill(Color(hex: seg.event.colorHex, brightness: 0.55))
            .frame(width: width, height: WidgetStyle.laneHeight - 1)
            .overlay(alignment: .leading) {
                Text(seg.event.title)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()               // full title; overlay width can't widen the bar
                    .foregroundStyle(.white)
                    .padding(.leading, 3)
            }
            .clipShape(shape)                  // title spans the bar, hard-clipped at its end
            .offset(x: x, y: y)
    }
}

/// A single day column: date number, reserved space for the week's all-day lanes, then timed rows.
struct ColumnView: View {
    let day: Date
    let timed: DayCellContent?
    let laneSpace: CGFloat
    let calendar: Calendar

    private var dayNumber: Int { calendar.component(.day, from: day) }
    private var isToday: Bool { calendar.isDateInToday(day) }
    private var isSunday: Bool { calendar.component(.weekday, from: day) == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(dayNumber)")
                .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isSunday ? WidgetStyle.accent : .white)
                .frame(height: WidgetStyle.dateHeight, alignment: .leading)
                .padding(.leading, 1)

            Color.clear.frame(height: laneSpace) // all-day bars are overlaid here by WeekRowView

            if let timed {
                ForEach(Array(timed.rows.enumerated()), id: \.offset) { _, row in
                    timedRow(row)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 1)
        .clipped()
        .contentShape(Rectangle()) // whole column tappable for the Link
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.white.opacity(isToday ? 0.5 : 0), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func timedRow(_ row: DayCellContent.Row) -> some View {
        switch row {
        case let .event(event):
            HStack(spacing: 3) {
                Capsule().fill(Color(hex: event.colorHex)).frame(width: 2, height: 8)
                Text(EventTextFormatter.line(for: event, calendar: calendar))
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.white)
            }
            .padding(.leading, 1)
            .clippedGridRow(height: WidgetStyle.timedRowHeight)
        case let .moreCount(n):
            Text("+\(n) more")
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.leading, 2)
                .clippedGridRow(height: WidgetStyle.timedRowHeight)
        }
    }
}
