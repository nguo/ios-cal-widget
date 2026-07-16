import SwiftUI

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
            }
        }
    }
}
