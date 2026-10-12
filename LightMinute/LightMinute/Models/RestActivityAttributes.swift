import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Shared between the app and the Dynamic Island widget extension.
struct RestActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Wall-clock instant the break ends — lets the widget count down on its own.
        var endDate: Date
        /// Total length of this break, for the progress ring.
        var totalDuration: TimeInterval
        var isLongRest: Bool
        var sessionsDone: Int
        var sessionsTotal: Int
    }

    /// Static for the life of the activity.
    var startedAt: Date
}
#endif
