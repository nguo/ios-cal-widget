import SwiftUI
import AppIntents
import CalCore

/// Top row: bold month label on the left; a "jump to today" button (shown only when paged
/// away) plus prev/next pagination chevrons and a refresh button on the right. Widgets run the
/// App Intents; the in-app preview renders the glyphs as static (running `Button(intent:)` from
/// the app errors with an XPC/helper failure).
struct MonthHeaderView: View {
    let monthLabel: String
    let isSyncing: Bool
    /// Non-nil (today's day-of-month) when the widget is paged away from today — shows the
    /// jump-to-today button with that number inside a mini calendar icon.
    var todayDayNumber: Int? = nil
    var interactive: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(monthLabel)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            if let todayDayNumber {
                control(intent: GoToTodayIntent()) { TodayIcon(day: todayDayNumber) }
            }
            control(intent: ShiftWindowIntent(direction: -1)) { navGlyph("chevron.left") }
            control(intent: ShiftWindowIntent(direction: 1)) { navGlyph("chevron.right") }
            control(intent: RefreshNowIntent(), disabled: isSyncing) {
                navGlyph("arrow.clockwise").opacity(isSyncing ? 0.35 : 1)
            }
        }
    }

    /// Renders `label` as a `Button(intent:)` in the widget, or a static glyph in the app preview.
    @ViewBuilder
    private func control<I: AppIntent, Label: View>(
        intent: I,
        disabled: Bool = false,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if interactive {
            Button(intent: intent, label: label)
                .buttonStyle(.plain)
                .disabled(disabled)
        } else {
            label()
        }
    }

    private func navGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.7))
            .frame(width: 22, height: 22)
    }
}

/// A compact calendar-date glyph (rounded box with a colored top strip and the day number),
/// echoing the iOS Calendar app icon.
struct TodayIcon: View {
    let day: Int

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(WidgetStyle.accent)
                .frame(height: 4)
            Text("\(day)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 18, height: 18)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
        )
    }
}
