import AppKit
import SwiftUI

/// Persist colors as six-digit sRGB strings, or use the current system accent.
enum ThemeColor {
    static let preferenceKey = "appearance.accentHex"
    static let systemValue = "system"
    static let presets: [(name: String, hex: String)] = [
        ("松石", "2D7168"), ("深海", "3A64A0"), ("暮紫", "65549A"),
        ("莓红", "9A4D6D"), ("陶土", "96523D"), ("古铜", "826331")
    ]

    static func color(_ value: String) -> Color {
        guard let rgb = components(value) else { return Color(nsColor: .controlAccentColor) }
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    static func hex(_ color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let values = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
            .map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", values[0], values[1], values[2])
    }

    /// Resolve the system color in the view's appearance so text remains legible
    /// when either the system accent or the selected custom color is light.
    static func keyInk(_ value: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb: (red: CGFloat, green: CGFloat, blue: CGFloat)
            if let fixed = components(value) {
                rgb = (CGFloat(fixed.red), CGFloat(fixed.green), CGFloat(fixed.blue))
            } else {
                var resolved = NSColor.black
                appearance.performAsCurrentDrawingAppearance {
                    resolved = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .black
                }
                rgb = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
            }
            func linear(_ component: CGFloat) -> CGFloat {
                component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
            return luminance > 0.179 ? .black : .white
        })
    }

    private static func components(_ value: String) -> (red: Double, green: Double, blue: Double)? {
        guard value.utf8.count == 6,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let rgb = UInt32(value, radix: 16) else { return nil }
        return (Double((rgb >> 16) & 255) / 255, Double((rgb >> 8) & 255) / 255, Double(rgb & 255) / 255)
    }
}
