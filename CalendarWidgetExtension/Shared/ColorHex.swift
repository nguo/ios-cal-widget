import SwiftUI

extension Color {
    /// Parses "#RRGGBB" / "RRGGBB" (and "#RGB"). Falls back to gray on bad input.
    /// `brightness` < 1 darkens the color (multiplies RGB) — used for all-day bar tints.
    init(hex: String, brightness: Double = 1.0) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .gray
            return
        }
        var r, g, b: Double
        switch cleaned.count {
        case 3: // RGB
            r = Double((value & 0xF00) >> 8) / 15
            g = Double((value & 0x0F0) >> 4) / 15
            b = Double(value & 0x00F) / 15
        default: // RRGGBB
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        }
        let k = max(0, min(1, brightness))
        r *= k; g *= k; b *= k
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
