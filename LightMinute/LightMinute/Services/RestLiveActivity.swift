import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Drives the Dynamic Island / Lock Screen break timer.
/// The widget counts down from `endDate` on its own, so the break keeps
/// running (and keeps displaying) while the app is backgrounded.
@MainActor
final class RestLiveActivity {

    #if canImport(ActivityKit)
    private var activity: Activity<RestActivityAttributes>?
    #endif

    func start(endDate: Date,
               total: TimeInterval,
               isLong: Bool,
               sessionsDone: Int,
               sessionsTotal: Int) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = RestActivityAttributes.ContentState(
            endDate: endDate,
            totalDuration: total,
            isLongRest: isLong,
            sessionsDone: sessionsDone,
            sessionsTotal: sessionsTotal
        )
        let content = ActivityContent(state: state,
                                      staleDate: endDate.addingTimeInterval(60))

        if let activity {
            Task { await activity.update(content) }
            return
        }
        activity = try? Activity.request(
            attributes: RestActivityAttributes(startedAt: Date()),
            content: content,
            pushType: nil
        )
        #endif
    }

    func stop() {
        #if canImport(ActivityKit)
        guard let current = activity else { return }
        activity = nil
        Task { await current.end(nil, dismissalPolicy: .immediate) }
        #endif
    }

    /// Clears anything left over from a previous launch (e.g. app force-quit mid-break).
    func clearStale() {
        #if canImport(ActivityKit)
        for a in Activity<RestActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }
}
