import SwiftUI
import CalCore
#if canImport(UIKit)
import UIKit
#endif

/// Shared visual constants for the widget.
enum WidgetStyle {
    /// Sunday-only accent color (also used by the today glyph).
    static let accent = Color(red: 0.29, green: 0.53, blue: 0.91) // ~#4A87E8 blue
    /// Dim dark-blue fill behind today's date pill — reads as "today" without competing
    /// with the calendar event colors below it.
    static let todayPillBackground = Color(red: 0.11, green: 0.20, blue: 0.33) // ~#1C3355
    /// Red used for declined events (title + strikethrough). Slightly desaturated so it reads as
    /// "declined" without shouting over the dark widget background.
    static let declinedColor = Color(red: 0.92, green: 0.35, blue: 0.35) // ~#EB5959

    // Row geometry shared between WeekRowView (bar offsets) and ColumnView (reserved space).
    static let dateHeight: CGFloat = 14
    static let laneHeight: CGFloat = 12   // all-day bar lane
    static let timedRowHeight: CGFloat = 11

    // Agenda widget row geometry. Shared between AgendaGroupView (rendering) and
    // AgendaPagination (the fit calculation that decides how many events a page holds), so
    // they MUST stay in sync — the page walk assumes rows render at exactly these heights.
    static let agendaDayHeaderHeight: CGFloat = 18
    static let agendaAllDayRowHeight: CGFloat = 16
    static let agendaTimedRowHeight: CGFloat = 30
    /// Fixed chrome above the day-groups: outer padding (top+bottom), the TODAY anchor + divider,
    /// and the spacing above the groups. Subtracted from the device's small-widget height to get
    /// the paging budget. Single tuning knob — bump it up if a full SE page still clips, down if a
    /// big-screen page wastes space at the bottom.
    static let agendaChrome: CGFloat = 58

    /// Height available for day-groups, derived from THIS device's systemSmall widget height so
    /// smaller phones page sooner (fewer events) than larger ones. WidgetKit gives the timeline
    /// provider no geometry, so the size is inferred from the screen. The fit math in
    /// `AgendaPagination` targets this; AgendaView also hard-clips as a safety net.
    static var agendaPageBudget: CGFloat {
        smallWidgetHeight() - agendaChrome
    }

    /// The row heights above, packaged for CalCore's page walk. This is the whole seam: the
    /// widget owns the measurements, `AgendaPagination` owns the algorithm and stays
    /// Foundation-only (and therefore testable off-device).
    static var agendaMetrics: AgendaMetrics {
        AgendaMetrics(
            dayHeaderHeight: Double(agendaDayHeaderHeight),
            allDayRowHeight: Double(agendaAllDayRowHeight),
            timedRowHeight: Double(agendaTimedRowHeight),
            pageBudget: Double(agendaPageBudget)
        )
    }

    // Medium agenda widget geometry. Uniform two-line event cards in the right column, a fixed
    // date column, and a slim paging rail on the left. AgendaMediumView renders to these and
    // AgendaPageSizing.fixedCount pages by them, so they MUST stay in sync.
    static let agendaMediumRowHeight: CGFloat = 32
    static let agendaMediumRowSpacing: CGFloat = 3
    static let agendaMediumDateColumnWidth: CGFloat = 44
    static let agendaMediumRailWidth: CGFloat = 32
    static let agendaMediumRailButtonSize: CGFloat = 26
    // The date column's two lines are pinned to explicit heights summing to the row height, so the
    // stacked weekday/day-number can't overflow its row and get cropped.
    static let agendaMediumWeekdayHeight: CGFloat = 11
    static let agendaMediumDayNumberHeight: CGFloat = 21
    /// Outer padding (top + bottom) — the medium layout has no header chrome above the rows.
    /// Kept tight (4pt a side) so a 4th card fits the smaller phones; the leftover on big screens
    /// is split evenly above/below the rows rather than pooling at the bottom.
    static let agendaMediumChrome: CGFloat = 8

    /// Events per page on the medium widget: whole cards that fit this device's widget height.
    /// `systemMedium` is the same height as `systemSmall` on iOS, so the same bucketed estimate
    /// applies. The trailing `+ spacing` accounts for the last row having no gap after it.
    static var agendaMediumRowsPerPage: Int {
        let budget = smallWidgetHeight() - agendaMediumChrome
        let pitch = agendaMediumRowHeight + agendaMediumRowSpacing
        return max(Int((budget + agendaMediumRowSpacing) / pitch), 1)
    }

    /// systemSmall widget point-height for the current device.
    ///
    /// Resolved from `UIScreen` exactly once, on whichever thread calls `primeDeviceMetrics()`
    /// first — `UIScreen` is main-thread-only, and timeline providers run on a background
    /// queue, so both entry points prime it at launch. A `static let` also means the screen is
    /// read once per process rather than on every page-fit calculation.
    static func smallWidgetHeight() -> CGFloat { deviceSmallWidgetHeight }

    private static let deviceSmallWidgetHeight: CGFloat = resolveSmallWidgetHeight()

    /// Forces the one `UIScreen` read to happen now, on the caller's thread. Call from the app
    /// and widget-bundle initializers (both main) so a background provider never triggers it.
    static func primeDeviceMetrics() {
        _ = deviceSmallWidgetHeight
    }

    /// Bucketed by screen long-side. Values are approximate — verify on real hardware and
    /// adjust. Falls back to a mid value off-device (e.g. previews).
    private static func resolveSmallWidgetHeight() -> CGFloat {
        #if canImport(UIKit)
        let longSide = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        switch longSide {
        case ..<600: return 141   // SE 1st gen (320×568)
        case ..<700: return 148   // SE 2/3, 6/7/8 (375×667)
        case ..<813: return 155   // X/XS/11 Pro, 12/13 mini (375×812)
        case ..<850: return 158   // 12/13/14, 15/16, non-Max Pro (390×844, 393×852)
        case ..<900: return 159   // XR/11, XS/11 Pro Max (414×896)
        case ..<930: return 169   // 12–13 Pro Max (428×926)
        default:     return 170   // 14–17 Pro Max & newer (430×932+)
        }
        #else
        return 158
        #endif
    }
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

/// One hard-clipped line of text (no ellipsis) at a fixed row height, built on
/// `clippedGridRow` so the text's natural width can't widen its container.
///
/// Both agenda views had a byte-identical private copy of this; it belongs here next to the
/// modifier it depends on.
struct ClippedLine: View {
    let string: String
    let size: CGFloat
    var weight: Font.Weight = .regular
    let color: Color
    let height: CGFloat
    var strikethrough: Bool = false

    var body: some View {
        Text(string)
            .font(.system(size: size, weight: weight))
            .lineLimit(1)
            .fixedSize()
            .strikethrough(strikethrough)
            .foregroundStyle(color)
            .clippedGridRow(height: height)
    }
}
