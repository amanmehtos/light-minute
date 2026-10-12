import SwiftUI

struct SessionDotsView: View {
    let total: Int
    let filled: Int
    let extraCount: Int

    var body: some View {
        HStack(spacing: 14) {
            if extraCount > 0 {
                ZStack {
                    Circle()
                        .fill(Theme.Color.timerText.opacity(0.2))
                        .frame(width: 30, height: 30)
                    Text("+\(extraCount)")
                        .font(.custom(Theme.pixelFont, size: 8))
                        .foregroundColor(Theme.Color.timerText)
                }
            }

            // A completed session is solid ink and sits proud of the page;
            // one still to come is an empty outline lying flat on it.
            ForEach(0..<total, id: \.self) { i in
                let done = i < filled
                Circle()
                    .fill(done ? Theme.Color.dotFilled : Theme.Color.sunken)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(done ? Theme.Color.dotFilled : Theme.Color.dotStroke,
                                          lineWidth: 2)
                    )
                    .diurnalElevation(done ? Theme.Elevation.input : Theme.Elevation.flat,
                                      shape: Circle())
            }
        }
    }
}
