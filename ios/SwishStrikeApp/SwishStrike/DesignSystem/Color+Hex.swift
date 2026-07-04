import SwiftUI

extension Color {
    /// Build a Color from a "#RRGGBB" or "#RRGGBBAA" hex string. Falls back to
    /// clear on a malformed string rather than crashing.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&v) else { self = .clear; return }
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((v & 0xFF0000) >> 16) / 255
            g = Double((v & 0x00FF00) >> 8) / 255
            b = Double(v & 0x0000FF) / 255
            a = 1
        case 8:
            r = Double((v & 0xFF000000) >> 24) / 255
            g = Double((v & 0x00FF0000) >> 16) / 255
            b = Double((v & 0x0000FF00) >> 8) / 255
            a = Double(v & 0x000000FF) / 255
        default:
            self = .clear; return
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
