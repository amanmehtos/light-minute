import SwiftUI

// Diurnal's elevation recipe, as published by the system:
//
//   box-shadow:
//     calc(dx*elev) calc(dy*elev) calc(blur*elev) rgb(shadow / alpha),      /* cast  */
//     calc(dx*1px)  calc(dy*1px)  1px rgb(shadow / min(1, alpha*1.6)),      /* contact */
//     inset calc(nx*-1px) calc(ny*-1px) 0 var(--dn-rim);                    /* lit rim */
//
// Three layers: the shadow the object throws, the darker seam where it meets the
// surface, and the rim of light on the edge that faces the source.

private struct DiurnalLightKey: EnvironmentKey {
    static let defaultValue = DiurnalLightState.skylight(moon: false)
}

extension EnvironmentValues {
    var diurnalLight: DiurnalLightState {
        get { self[DiurnalLightKey.self] }
        set { self[DiurnalLightKey.self] = newValue }
    }
}

struct DiurnalElevation<S: InsettableShape>: ViewModifier {
    let elevation: CGFloat
    let shape: S

    @Environment(\.diurnalLight) private var light
    @Environment(\.colorScheme)  private var scheme

    private var rim: Color {
        let base = scheme == .dark ? Theme.rimNight : Theme.rimDay
        let k    = scheme == .dark ? Theme.rimNightK : Theme.rimDayK
        return base.opacity(k * Double(light.rimK))
    }

    private var shadowInk: Color {
        Color(Theme.shadowInk.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)))
    }

    func body(content: Content) -> some View {
        guard elevation > 0 else { return AnyView(content) }

        // CSS blur-radius spans roughly twice SwiftUI's shadow radius.
        let castRadius = light.blur * elevation / 2
        let contact    = min(1, light.alpha * 1.6)

        return AnyView(
            content
                .overlay(
                    shape
                        .strokeBorder(rim, lineWidth: 1)
                        .offset(x: -light.nx, y: -light.ny)
                        .clipShape(shape)
                        .allowsHitTesting(false)
                )
                .shadow(color: shadowInk.opacity(Double(contact)),
                        radius: 0.5, x: light.dx, y: light.dy)
                .shadow(color: shadowInk.opacity(Double(light.alpha)),
                        radius: castRadius,
                        x: light.dx * elevation,
                        y: light.dy * elevation)
                .animation(Theme.lightEase, value: light)
        )
    }
}

extension View {
    /// Raise this view off the page by `elevation` points. Everything about how it
    /// is lit follows from where the sun or moon currently is.
    func diurnalElevation<S: InsettableShape>(_ elevation: CGFloat, shape: S) -> some View {
        modifier(DiurnalElevation(elevation: elevation, shape: shape))
    }

    func diurnalElevation(_ elevation: CGFloat, cornerRadius: CGFloat = Theme.radius) -> some View {
        modifier(DiurnalElevation(elevation: elevation,
                                  shape: RoundedRectangle(cornerRadius: cornerRadius,
                                                          style: .continuous)))
    }
}
