import SwiftUI

/// MIKE has no face any more — the illustration is gone and he is only a voice.
/// One quiet line of ink, no avatar and no bubble. Anger reads as full-strength
/// ink instead of the muted weight the line normally carries: the system is
/// monochrome, so emphasis is contrast, never colour.
///
/// What this stretch of time is being filed under sits above him, quieter
/// still. It is a label on the recording rather than something to read, so it
/// is the faintest thing on the screen and never wraps — what matters is that a
/// glance says what is being counted. The view is handed the line rather than
/// deriving it: whether that is a Light Week task or simply what the timer is
/// doing is not a header's business.
struct MikeHeaderView: View {
    let message: String
    var angry: Bool = false
    var focus: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            if let focus {
                Text(focus)
                    .font(.custom(Theme.pixelFont, size: 7))
                    .foregroundColor(Theme.Color.timerText.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 28)
            }

            Text(message)
                .font(.custom(Theme.pixelFont, size: 8))
                .foregroundColor(Theme.Color.timerText.opacity(angry ? 1.0 : 0.5))
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, focus == nil ? 18 : 10)
        .animation(.easeInOut(duration: 0.2), value: angry)
    }

}
