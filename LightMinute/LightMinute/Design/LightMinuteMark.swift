import SwiftUI

/// The app mark, drawn rather than imported.
///
/// A run of equal marks climbing to a larger lit head — a light minute is a
/// distance, so the mark measures one. The geometry is the same 32×32 cell
/// grid the app icon is cut from, kept here as the single definition so the
/// Dynamic Island and the icon can't drift apart.
///
/// The trail is flat ink at full strength, never faded: the run has to stay
/// countable, and marks that fade toward the ground vanish first at the sizes
/// where that matters most.
struct LightMinuteMark: View {

    /// How many trail marks to draw, head excluded. Five is the icon.
    /// Below roughly 24pt the full run turns to noise — the Dynamic Island
    /// uses a shorter one, which reads as the same mark zoomed in.
    var trail: Int = 5

    private struct Cell {
        let x, y, w, h: Int
    }

    /// Marks climb 4 cells right and 3 up at a time; the head is twice their
    /// size and continues the same climb.
    private static let marks = (0..<5).map { Cell(x: 3 + $0 * 4, y: 23 - $0 * 3, w: 3, h: 3) }
    private static let head = Cell(x: 23, y: 5, w: 6, h: 6)

    var body: some View {
        let shown = Self.marks.suffix(min(max(trail, 1), Self.marks.count)) + [Self.head]
        let minX = shown.map(\.x).min() ?? 0
        let minY = shown.map(\.y).min() ?? 0
        let spanX = (shown.map { $0.x + $0.w }.max() ?? 1) - minX
        let spanY = (shown.map { $0.y + $0.h }.max() ?? 1) - minY
        let span = max(spanX, spanY)

        GeometryReader { geo in
            // One cell, sized so the drawn run fills the frame on its long axis.
            let unit = min(geo.size.width, geo.size.height) / CGFloat(span)
            let ox = (geo.size.width - CGFloat(spanX) * unit) / 2
            let oy = (geo.size.height - CGFloat(spanY) * unit) / 2

            ForEach(Array(shown.enumerated()), id: \.offset) { _, cell in
                Rectangle()
                    .frame(width: CGFloat(cell.w) * unit, height: CGFloat(cell.h) * unit)
                    .offset(x: ox + CGFloat(cell.x - minX) * unit,
                            y: oy + CGFloat(cell.y - minY) * unit)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    HStack(spacing: 20) {
        ForEach([5, 3, 2], id: \.self) { n in
            LightMinuteMark(trail: n)
                .foregroundColor(Theme.Color.timerText)
                .frame(width: 48, height: 48)
        }
    }
    .padding()
    .background(Theme.Color.background)
}
