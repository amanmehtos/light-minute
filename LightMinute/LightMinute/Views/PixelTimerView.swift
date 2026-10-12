import SwiftUI
import UIKit

// MARK: – Single pixel number at an explicit font size

struct PixelNumber: UIViewRepresentable {
    let value: Int
    let outline: Bool
    let fontSize: CGFloat

    // Taking the scheme as an explicit dependency makes UIKit re-resolve the
    // adaptive ink whenever Diurnal / Nocturnal flips.
    @Environment(\.colorScheme) private var scheme

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.backgroundColor = .clear
        label.textAlignment   = .center
        label.numberOfLines   = 1
        label.clipsToBounds   = true
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        let text = String(format: "%02d", value)
        let font = UIFont(name: "PressStart2P-Regular", size: fontSize)
            ?? UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .black)
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let fill   = Theme.uiTimerText.resolvedColor(with: traits)

        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if outline {
            attrs[.foregroundColor] = UIColor.clear
            attrs[.strokeColor]     = fill
            attrs[.strokeWidth]     = NSNumber(value: 5)   // positive = stroke only
        } else {
            attrs[.foregroundColor] = fill
            attrs[.strokeColor]     = fill
            attrs[.strokeWidth]     = NSNumber(value: -2)  // negative = fill + thin stroke
        }
        uiView.attributedText = NSAttributedString(string: text, attributes: attrs)
    }
}

// MARK: – Full timer — pass an explicit fontSize calculated outside

struct PixelTimerView: View {
    let minutes:   Int
    let seconds:   Int
    let isOutline: Bool
    let fontSize:  CGFloat     // caller calculates this from screen geometry

    private var rowHeight: CGFloat { fontSize }          // line height ≈ fontSize for Press Start 2P
    private var sepSize:   CGFloat { max(fontSize * 0.10, 8) }

    init(minutes: Int, seconds: Int, isOutline: Bool = false, fontSize: CGFloat) {
        self.minutes   = minutes
        self.seconds   = seconds
        self.isOutline = isOutline
        self.fontSize  = fontSize
    }

    var body: some View {
        VStack(spacing: 0) {
            PixelNumber(value: minutes, outline: isOutline, fontSize: fontSize)
                .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight)

            HStack(spacing: fontSize * 0.22) {
                dot; dot
            }
            .frame(height: sepSize + fontSize * 0.06)

            PixelNumber(value: seconds, outline: isOutline, fontSize: fontSize)
                .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight)
        }
    }

    private var dot: some View {
        Rectangle()
            .fill(isOutline
                  ? Theme.Color.timerText.opacity(0.35)
                  : Theme.Color.timerText)
            .frame(width: sepSize, height: sepSize)
    }
}

// MARK: – Helper: compute fontSize from an available bounding box
// Press Start 2P empirical metrics (measured from renders):
//   2-digit string width  ≈ fontSize × 2.44
//   line height           ≈ fontSize × 1.00
//   full timer height     ≈ fontSize × 2.20  (2 rows + separator)
extension CGFloat {
    static func timerFontSize(in box: CGSize, fillRatio: CGFloat = 0.88) -> CGFloat {
        let fromWidth  = box.width  * fillRatio / 2.44
        let fromHeight = box.height * fillRatio / 2.20
        return Swift.min(fromWidth, fromHeight)
    }
}

// MARK: – Compact rest timer

struct CompactRestTimer: View {
    let minutes: Int
    let seconds: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(String(format: "%02d", minutes))
                .font(.custom(Theme.pixelFont, size: 28))
                .foregroundColor(Theme.Color.timerText)
            Text(":")
                .font(.custom(Theme.pixelFont, size: 28))
                .foregroundColor(Theme.Color.timerText.opacity(0.5))
            Text(String(format: "%02d", seconds))
                .font(.custom(Theme.pixelFont, size: 28))
                .foregroundColor(Theme.Color.timerText)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.Color.timerText.opacity(0.2), lineWidth: 1.5)
        )
    }
}
