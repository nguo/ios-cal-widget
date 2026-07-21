import SwiftUI
import WidgetKit

/// The "S M T W T F S" row. Only Sunday (first column) is accented.
struct WeekdayHeaderRow: View {
    private let symbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(index == 0 ? WidgetStyle.accent : Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    // Sunday's blue is flattened when the system recolors the widget. Putting
                    // just this column in the accent group keeps it distinguishable there too.
                    .widgetAccentable(index == 0)
            }
        }
    }
}
