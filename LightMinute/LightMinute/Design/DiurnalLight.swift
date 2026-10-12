import SwiftUI
import Foundation

// Diurnal UI's light model.
//
//   "Light mode is lit by the sun, dark mode by the full moon, which sits
//    opposite the sun: it rises at sunset, peaks at midnight and sets at dawn."
//
// The interface is treated as a flat surface seen from above, north up. The light
// sits at its real compass bearing, and shadows fall away from it: a low light
// casts long shadows, a high one short. The curves below were derived by sampling
// the live system across a full day and fitting to the observed values.

/// Shadow geometry for one instant, in units of elevation.
struct DiurnalLightState: Equatable {
    var isUp: Bool      // light above the horizon
    var nx: CGFloat     // unit shadow direction; the rim sits on the opposite edge
    var ny: CGFloat
    var dx: CGFloat     // offset per point of elevation
    var dy: CGFloat
    var blur: CGFloat   // blur per point of elevation
    var alpha: CGFloat  // shadow strength
    var rimK: CGFloat   // lit-rim multiplier

    /// Light below the horizon: only soft skylight remains, falling straight down.
    static func skylight(moon: Bool) -> DiurnalLightState {
        DiurnalLightState(isUp: false, nx: 0, ny: 1, dx: 0, dy: 0.45,
                          blur: moon ? 3.0 : 2.4,
                          alpha: moon ? 0.5 : 0.16,
                          rimK: 0.25)
    }
}

enum DiurnalLight {

    /// Shadow state for a body at the given altitude/azimuth in degrees.
    static func shadow(altitude: Double, azimuth: Double, moon: Bool) -> DiurnalLightState {
        guard altitude > 0 else { return .skylight(moon: moon) }

        // Length grows as the light drops; clamped so a light near the horizon
        // doesn't throw a shadow off the edge of the world.
        let length = min(3.2, 1.0 / tan(altitude * .pi / 180) + 0.25)

        let az = azimuth * .pi / 180
        let nx = -sin(az), ny = cos(az)   // away from the light, north up

        // Moonlight is softer than sunlight — the same slope, lifted baseline.
        let blur = (moon ? 1.30 : 0.45) + 0.25 * length

        // Against a dark ground the moon's shadows are near-opaque; by day they
        // thin out as the sun approaches the horizon and the light reddens.
        let alpha = moon ? 0.95 : min(0.42, 0.232 + 0.00714 * altitude)

        return DiurnalLightState(
            isUp: true,
            nx: CGFloat(nx), ny: CGFloat(ny),
            dx: CGFloat(length * nx), dy: CGFloat(length * ny),
            blur: CGFloat(blur), alpha: CGFloat(alpha), rimK: 1
        )
    }

    /// Shadow state for `date` at `place`, lit by the sun or by the full moon.
    static func state(at date: Date, place: Place, moon: Bool) -> DiurnalLightState {
        let sun = solarPosition(date: date, latitude: place.latitude, longitude: place.longitude)
        // The full moon is the sun's antipode: negate the altitude, flip the bearing.
        return moon
            ? shadow(altitude: -sun.altitude, azimuth: sun.azimuth + 180, moon: true)
            : shadow(altitude:  sun.altitude, azimuth: sun.azimuth,       moon: false)
    }

    // MARK: – Where the sun is

    struct Place: Equatable {
        var latitude: Double
        var longitude: Double

        /// No location permission is asked for. Longitude comes from the device's
        /// UTC offset, which is accurate to within a time zone's width; latitude
        /// falls back to the Diurnal reference until something better is supplied.
        static var deviceApproximate: Place {
            let hours = Double(TimeZone.current.secondsFromGMT()) / 3600
            return Place(latitude: 20, longitude: (hours * 15).clampedLongitude)
        }
    }

    /// Altitude and azimuth (degrees, azimuth from north, clockwise).
    /// Low-precision NOAA solar position — well inside the tolerance of a shadow.
    static func solarPosition(date: Date, latitude: Double, longitude: Double)
        -> (altitude: Double, azimuth: Double) {

        let rad = Double.pi / 180
        let days = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0

        let meanLongitude = (280.460 + 0.9856474 * days).normalizedDegrees
        let meanAnomaly   = (357.528 + 0.9856003 * days).normalizedDegrees * rad

        // Apparent ecliptic longitude
        let lambda = (meanLongitude
                      + 1.915 * sin(meanAnomaly)
                      + 0.020 * sin(2 * meanAnomaly)).normalizedDegrees * rad
        let obliquity = (23.439 - 0.0000004 * days) * rad

        let rightAscension = atan2(cos(obliquity) * sin(lambda), cos(lambda))
        let declination    = asin(sin(obliquity) * sin(lambda))

        // Greenwich mean sidereal time → local hour angle
        let gmst = (18.697375 + 24.065709824279 * days).truncatingRemainder(dividingBy: 24)
        let lst  = (gmst * 15 + longitude).normalizedDegrees * rad
        let hourAngle = lst - rightAscension

        let phi = latitude * rad
        let altitude = asin(sin(phi) * sin(declination)
                            + cos(phi) * cos(declination) * cos(hourAngle))

        // Measured from south, westward — then rotated to a compass bearing.
        let azimuthFromSouth = atan2(sin(hourAngle),
                                     cos(hourAngle) * sin(phi) - tan(declination) * cos(phi))

        return (altitude / rad, (azimuthFromSouth / rad + 180).normalizedDegrees)
    }
}

private extension Double {
    var normalizedDegrees: Double {
        let v = truncatingRemainder(dividingBy: 360)
        return v < 0 ? v + 360 : v
    }
    var clampedLongitude: Double { Swift.max(-180, Swift.min(180, self)) }
}

// MARK: – The sky, as an observable

/// Publishes the current light. The sun moves slowly, so this ticks once a minute;
/// every shadow in the app is a function of this one value.
@MainActor
final class DiurnalSky: ObservableObject {
    @Published private(set) var light: DiurnalLightState = .skylight(moon: false)

    var place: DiurnalLight.Place = .deviceApproximate { didSet { refresh() } }
    var isMoonlit: Bool = false { didSet { if isMoonlit != oldValue { refresh() } } }

    private var ticker: Timer?

    init() { refresh() }

    func start() {
        refresh()
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    func refresh() {
        light = DiurnalLight.state(at: Date(), place: place, moon: isMoonlit)
    }
}
