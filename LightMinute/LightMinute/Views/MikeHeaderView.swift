import SwiftUI

/// MIKE has no face any more — the illustration is gone and he is only a voice.
/// One quiet line of ink, no avatar and no bubble. Anger reads as full-strength
/// ink instead of the muted weight the line normally carries: the system is
/// monochrome, so emphasis is contrast, never colour.
struct MikeHeaderView: View {
    let message: String
    var angry: Bool = false

    var body: some View {
        Text(message)
            .font(.custom(Theme.pixelFont, size: 8))
            .foregroundColor(Theme.Color.timerText.opacity(angry ? 1.0 : 0.5))
            .lineSpacing(6)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .animation(.easeInOut(duration: 0.2), value: angry)
    }
}
