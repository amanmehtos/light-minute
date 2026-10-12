import SwiftUI

struct PixelButton: View {
    let label: String
    let icon: String?
    let action: () -> Void

    init(_ label: String, icon: String? = nil, action: @escaping () -> Void) {
        self.label  = label
        self.icon   = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                }
                // Press Start 2P at 16pt (2× native 8px) — crisp, no stretch
                Text(label)
                    .font(.custom(Theme.pixelFont, size: 16))
            }
            .foregroundColor(Theme.Color.buttonText)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Theme.Color.buttonBg)
            .clipShape(Capsule())
        }
        .buttonStyle(DiurnalButtonStyle())
    }
}

/// "Buttons squeeze the instant you press, not on release… Only transform and
/// opacity animate, so shadows are never repainted mid-gesture." The elevation
/// drops from 6 to 3 on press, so the button settles toward the page.
struct DiurnalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .diurnalElevation(configuration.isPressed ? Theme.Elevation.pressed
                                                      : Theme.Elevation.button,
                              shape: Capsule())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
