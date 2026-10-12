import ActivityKit
import WidgetKit
import SwiftUI

// MARK: – Live Activity / Dynamic Island for the break timer

struct RestLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in

            // Lock screen / banner presentation
            LockScreenRestView(state: context.state)
                .activityBackgroundTint(Theme.Color.background)
                .activitySystemActionForegroundColor(Theme.Color.timerText)

        } dynamicIsland: { context in

            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.isLongRest ? "LONG REST" : "SHORT REST")
                            .font(.custom(Theme.pixelFont, size: 8))
                            .foregroundColor(Theme.Color.textSecondary)
                        Text("MIKE: RECHARGE")
                            .font(.custom(Theme.pixelFont, size: 8))
                            .foregroundColor(Theme.Color.timerText)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.range, countsDown: true)
                        .font(.custom(Theme.pixelFont, size: 16))
                        .foregroundColor(Theme.Color.timerText)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 92)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(timerInterval: context.state.range, countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(Theme.Color.timerText)

                        Text("SESSION \(context.state.sessionsDone) / \(context.state.sessionsTotal)")
                            .font(.custom(Theme.pixelFont, size: 8))
                            .foregroundColor(Theme.Color.textSecondary)
                    }
                    .padding(.top, 2)
                }

            } compactLeading: {
                // The app mark, not a rest glyph. This slot is where the system
                // says which app is talking, so it has to match the icon; the
                // fact that it's a break is carried by the expanded view's text.
                LightMinuteMark(trail: 3)
                    .foregroundColor(Theme.Color.timerText)
                    .padding(.vertical, 3)

            } compactTrailing: {
                Text(timerInterval: context.state.range, countsDown: true)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.Color.timerText)
                    .frame(width: 44)

            } minimal: {
                // Smallest presentation there is — the run drops to two marks
                // and a head, which reads as the same mark zoomed in.
                LightMinuteMark(trail: 2)
                    .foregroundColor(Theme.Color.timerText)
                    .padding(2)
            }
            .keylineTint(Theme.Color.timerText)
        }
    }
}

// MARK: – Lock screen presentation

private struct LockScreenRestView: View {
    let state: RestActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.isLongRest ? "LONG REST" : "SHORT REST")
                    .font(.custom(Theme.pixelFont, size: 8))
                    .foregroundColor(Theme.Color.textSecondary)

                ProgressView(timerInterval: state.range, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(Theme.Color.timerText)
            }

            Spacer(minLength: 4)

            Text(timerInterval: state.range, countsDown: true)
                .font(.custom(Theme.pixelFont, size: 16))
                .foregroundColor(Theme.Color.timerText)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: – Helpers

extension RestActivityAttributes.ContentState {
    /// Start…end window the system uses to render a self-updating countdown.
    var range: ClosedRange<Date> {
        let start = endDate.addingTimeInterval(-max(totalDuration, 1))
        return start...endDate
    }
}
