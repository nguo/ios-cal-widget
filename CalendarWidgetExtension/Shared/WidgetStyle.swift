import SwiftUI
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
    // AgendaEntryBuilder (the fit calculation that decides how many events a page holds), so
    // they MUST stay in sync — the builder assumes rows render at exactly these heights.
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
    /// AgendaEntryBuilder targets this; AgendaView also hard-clips as a safety net.
    static var agendaPageBudget: CGFloat {
        smallWidgetHeight() - agendaChrome
    }

    /// systemSmall widget point-height for the current device, bucketed by screen long-side.
    /// Values are approximate — verify on real hardware and adjust. Falls back to a mid value
    /// off-device (e.g. previews).
    private static func smallWidgetHeight() -> CGFloat {
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
