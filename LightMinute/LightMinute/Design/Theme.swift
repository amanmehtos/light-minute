import SwiftUI
import UIKit

enum Theme {

    // Diurnal UI tokens, read from the live system at pantheon.monastichill.com/diurnal.
    // "Monochrome only: ink, paper and greys, nothing else." No hue anywhere except the
    // moonlit rim, which is the one place the system allows a tint.

    /// Lit by the sun.
    private enum Day {
        static let bg          = "#EFEFED"   // --dn-bg
        static let surface     = "#FAFAF9"   // --dn-surface
        static let raised      = "#FFFFFF"   // --dn-raised
        static let sunken      = "#E6E6E3"   // --dn-sunken
        static let ink         = "#141414"   // --dn-ink
        static let ink2        = "#3D3D3C"   // --dn-ink-2
        static let muted       = "#6E6E6B"   // --dn-muted
        static let line        = "#D3D3CF"   // --dn-line
        static let lineStrong  = "#A9A9A4"   // --dn-line-strong
    }

    /// Lit by the full moon, which sits opposite the sun.
    private enum Night {
        static let bg          = "#0B0B0C"
        static let surface     = "#18181A"
        static let raised      = "#242427"
        static let sunken      = "#0E0E0F"
        static let ink         = "#ECECEA"
        static let ink2        = "#C2C2BF"
        static let muted       = "#85857F"
        static let line        = "#2E2E31"
        static let lineStrong  = "#4A4A4F"
    }

    enum Color {
        static let background    = Theme.adaptive(Day.bg,      Night.bg)
        static let surface       = Theme.adaptive(Day.surface, Night.surface)
        static let surfaceHigh   = Theme.adaptive(Day.raised,  Night.raised)
        static let sunken        = Theme.adaptive(Day.sunken,  Night.sunken)
        static let border        = Theme.adaptive(Day.line,       Night.line)
        static let borderStrong  = Theme.adaptive(Day.lineStrong, Night.lineStrong)

        // Timer & text
        static let timerText     = Theme.adaptive(Day.ink,   Night.ink)
        static let textPrimary   = Theme.adaptive(Day.ink,   Night.ink)
        static let textSecondary = Theme.adaptive(Day.muted, Night.muted)

        // Buttons are raised material carrying ink, not inverted pills —
        // emphasis in Diurnal comes from elevation, not from a fill flip.
        static let buttonBg      = Theme.adaptive(Day.raised, Night.raised)
        static let buttonText    = Theme.adaptive(Day.ink,    Night.ink)

        // Session dots
        static let dotStroke     = Theme.adaptive(Day.lineStrong, Night.lineStrong)
        static let dotFilled     = Theme.adaptive(Day.ink,        Night.ink)

        // Dialog
        static let dialogBg      = Theme.adaptive(Day.surface, Night.surface)
        static let dialogBorder  = Theme.adaptive(Day.line,    Night.line)

        // Checkbox (settings)
        static let checkboxBg     = Theme.adaptive(Day.raised,     Night.raised)
        static let checkboxBorder = Theme.adaptive(Day.lineStrong, Night.lineStrong)
    }

    /// `rgb(var(--dn-shadow-rgb) / …)` — warm-black by day, pure black by moonlight.
    static let shadowInk = UIColor.adaptive("#141210", "#000000")

    /// `--dn-rim` base: near-white sunlight, cool moonlight. Alpha is applied per frame
    /// from the light state (`0.95 · rimK` by day, `0.32 · rimK` by night).
    static let rimDay   = SwiftUI.Color(hex: "#FFFFFF")
    static let rimNight = SwiftUI.Color(hex: "#D6DEF0")
    static let rimDayK: Double   = 0.95
    static let rimNightK: Double = 0.32

    // --dn-radius / --dn-radius-sm
    static let radius:   CGFloat = 8
    static let radiusSM: CGFloat = 6

    /// --dn-elev, per component, in points.
    enum Elevation {
        static let flat:     CGFloat = 0
        static let input:    CGFloat = 2
        static let pressed:  CGFloat = 3
        static let button:   CGFloat = 6
        static let prose:    CGFloat = 14
        static let card:     CGFloat = 18
        static let sheet:    CGFloat = 30
    }

    /// --dn-ease: the light moves slowly; nothing about it should snap.
    static let lightEase = SwiftUI.Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 1.6)

    /// UIKit-side timer ink — used by `PixelNumber`'s UILabel.
    static let uiTimerText = UIColor.adaptive(Day.ink, Night.ink)

    // Press Start 2P — render at multiples of 8 for crisp pixels
    static let pixelFont = "PressStart2P-Regular"
    static let fontXS:  CGFloat = 8
    static let fontSM:  CGFloat = 8    // smallest readable pixel size
    static let fontMD:  CGFloat = 16   // buttons, labels
    static let fontLG:  CGFloat = 24   // section titles

    fileprivate static func adaptive(_ day: String, _ night: String) -> SwiftUI.Color {
        SwiftUI.Color(UIColor.adaptive(day, night))
    }
}

extension UIColor {
    /// Resolves per trait collection, so the whole palette follows `preferredColorScheme`.
    static func adaptive(_ day: String, _ night: String) -> UIColor {
        let d = UIColor(hex: day), n = UIColor(hex: night)
        return UIColor { $0.userInterfaceStyle == .dark ? n : d }
    }

    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red:   CGFloat(r) / 255,
                  green: CGFloat(g) / 255,
                  blue:  CGFloat(b) / 255,
                  alpha: CGFloat(a) / 255)
    }
}

extension SwiftUI.Color {
    init(hex: String) { self.init(UIColor(hex: hex)) }
}
