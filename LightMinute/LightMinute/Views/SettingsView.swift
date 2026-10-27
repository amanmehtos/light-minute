import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: TimerViewModel

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                MikeHeaderView(message: vm.mikeMessage)
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // Title
                        Text("SETTINGS")
                            .font(.custom(Theme.pixelFont, size: 16))
                            .foregroundColor(Theme.Color.timerText)
                            .padding(.bottom, 4)

                        // ── Timer Durations ──────────────────────────────
                        sectionLabel("TIMER")

                        ArrowRow(label: "FOCUS",
                                 value: Int(vm.settings.focusDuration / 60), unit: "MIN",
                                 onMinus: { if vm.settings.focusDuration > 60  { vm.settings.focusDuration -= 60 }
                                           vm.reset() },
                                 onPlus:  { if vm.settings.focusDuration < 3600 { vm.settings.focusDuration += 60 }
                                           vm.reset() })

                        ArrowRow(label: "SHORT BREAK",
                                 value: Int(vm.settings.shortRestDuration / 60), unit: "MIN",
                                 onMinus: { if vm.settings.shortRestDuration > 60   { vm.settings.shortRestDuration -= 60 } },
                                 onPlus:  { if vm.settings.shortRestDuration < 1800 { vm.settings.shortRestDuration += 60 } })

                        ArrowRow(label: "LONG BREAK",
                                 value: Int(vm.settings.longRestDuration / 60), unit: "MIN",
                                 onMinus: { if vm.settings.longRestDuration > 60   { vm.settings.longRestDuration -= 60 } },
                                 onPlus:  { if vm.settings.longRestDuration < 3600 { vm.settings.longRestDuration += 60 } })

                        ArrowRow(label: "SESSIONS",
                                 value: vm.settings.sessions, unit: "",
                                 onMinus: { if vm.settings.sessions > 1  { vm.settings.sessions -= 1 } },
                                 onPlus:  { if vm.settings.sessions < 10 { vm.settings.sessions += 1 } })

                        divider

                        // ── Focus Mode ───────────────────────────────────
                        sectionLabel("FOCUS MODE")

                        PixelCheckbox(
                            label: "FLOWMODORO",
                            detail: "Keep focus running past target",
                            isOn: $vm.settings.flowModoro
                        )

                        PixelCheckbox(
                            label: "FLOW BREAKS",
                            detail: "Proportional rest from overflow time",
                            isOn: $vm.settings.flowBreaks,
                            disabled: !vm.settings.flowModoro
                        )

                        divider

                        // ── Target ───────────────────────────────────────
                        sectionLabel("TARGET")

                        ArrowRow(label: "DAILY TARGET",
                                 value: vm.settings.dailyTarget, unit: "SESSIONS",
                                 onMinus: { if vm.settings.dailyTarget > 1  { vm.settings.dailyTarget -= 1 } },
                                 onPlus:  { if vm.settings.dailyTarget < 24 { vm.settings.dailyTarget += 1 } })

                        DailyTargetProgress(done: vm.today.completed,
                                            target: vm.settings.dailyTarget,
                                            fraction: vm.targetFraction,
                                            reached: vm.targetReached)

                        divider

                        // ── Interface ────────────────────────────────────
                        sectionLabel("INTERFACE")

                        PixelCheckbox(
                            label: "DARK MODE",
                            detail: "Lit by the full moon instead of the sun",
                            isOn: $vm.settings.darkMode
                        )

                        PixelCheckbox(
                            label: "FLIP FOCUS",
                            detail: "Face-down starts · face-up pauses",
                            isOn: $vm.settings.flipFocus
                        )

                        divider

                        // ── Light Week ───────────────────────────────────
                        sectionLabel("LIGHT WEEK")

                        LightWeekSection(vm: vm)

                        // Exit
                        HStack {
                            Spacer()
                            PixelButton("Exit", icon: "xmark") {
                            vm.closeSettings()
                        }
                            Spacer()
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .preferredColorScheme(vm.colorScheme)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.custom(Theme.pixelFont, size: 8))
            .foregroundColor(Theme.Color.timerText.opacity(0.5))
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Color.border)
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

// MARK: – Light Week

/// Connecting an account, and seeing which one.
///
/// Everything here is optional and says so: Light Minute is a whole timer
/// without an account, and this section is the only place that admits one
/// exists. It sits at the bottom for that reason.
struct LightWeekSection: View {
    @ObservedObject var vm: TimerViewModel
    @ObservedObject private var auth: LightWeekAuth
    @ObservedObject private var outbox: FocusOutbox

    init(vm: TimerViewModel) {
        self.vm = vm
        // The timer owns these; the section only watches them, and has to watch
        // them directly because a change inside a nested object does not reach
        // a view observing only the object that holds it.
        _auth = ObservedObject(wrappedValue: vm.auth)
        _outbox = ObservedObject(wrappedValue: vm.outbox)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch auth.state {
            case .signedOut:
                detail("Log finished sessions against a Light Week task. The timer works the same either way.")
                HStack {
                    PixelButton("Connect", icon: "link") {
                        Task { await auth.signIn() }
                    }
                    Spacer()
                }

            case .signingIn:
                detail("Waiting for Light Week…")

            case .signedIn(let email):
                row("ACCOUNT", email ?? "CONNECTED")
                if !outbox.pending.isEmpty {
                    // Worth saying out loud: a session that has not reached the
                    // account yet is not a session that was lost.
                    detail("\(outbox.pending.count) session\(outbox.pending.count == 1 ? "" : "s") waiting to send.")
                }
                chip("DISCONNECT") { vm.disconnectLightWeek() }
            }

            if let task = vm.boundTask {
                Rectangle()
                    .fill(Theme.Color.border)
                    .frame(height: 1)
                    .padding(.vertical, 2)
                row("COUNTING", task.title.uppercased())
                chip("STOP COUNTING") { vm.unbind() }
            }

            if let error = auth.lastError ?? outbox.lastError {
                detail(error)
            }
        }
        .padding(.vertical, 2)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.custom(Theme.pixelFont, size: 7))
                .foregroundColor(Theme.Color.timerText.opacity(0.45))
            Spacer()
            Text(value)
                .font(.custom(Theme.pixelFont, size: 7))
                .foregroundColor(Theme.Color.timerText.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.custom(Theme.pixelFont, size: 7))
            .foregroundColor(Theme.Color.timerText.opacity(0.4))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A small raised chip, so a secondary action still catches the one light
    /// everything else in the app is lit by.
    private func chip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom(Theme.pixelFont, size: 7))
                .foregroundColor(Theme.Color.timerText.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(Theme.Color.checkboxBg)
                        .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: 1))
                )
                .diurnalElevation(Theme.Elevation.input, shape: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Arrow row (duration picker)

struct ArrowRow: View {
    let label: String
    let value: Int
    let unit: String
    let onMinus: () -> Void
    let onPlus:  () -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.custom(Theme.pixelFont, size: 8))
                .foregroundColor(Theme.Color.timerText)
            Spacer()
            Button(action: onMinus) {
                Image(systemName: "arrowtriangle.left.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Color.timerText)
            }.buttonStyle(.plain)

            Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                .font(.custom(Theme.pixelFont, size: 8))
                .foregroundColor(Theme.Color.timerText)
                .frame(minWidth: 64, alignment: .center)

            Button(action: onPlus) {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Color.timerText)
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: – Today's progress against the daily target

/// How far into today's target the user is. Monochrome: the track is sunken
/// into the page and the done portion is solid ink lying in it.
struct DailyTargetProgress: View {
    let done: Int
    let target: Int
    let fraction: Double
    let reached: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(reached ? "TARGET MET" : "TODAY")
                    .font(.custom(Theme.pixelFont, size: 7))
                    .foregroundColor(Theme.Color.timerText.opacity(reached ? 0.85 : 0.45))
                Spacer()
                Text("\(done) / \(target)")
                    .font(.custom(Theme.pixelFont, size: 7))
                    .foregroundColor(Theme.Color.timerText.opacity(0.85))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Color.sunken)
                    Capsule()
                        .fill(Theme.Color.dotFilled)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: 1))

            Text("Counts finished focus sessions · resets at midnight")
                .font(.custom(Theme.pixelFont, size: 7))
                .foregroundColor(Theme.Color.timerText.opacity(0.3))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

// MARK: – Pixel checkbox with description

struct PixelCheckbox: View {
    let label: String
    let detail: String
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Button { if !disabled { isOn.toggle() } } label: {
            HStack(alignment: .top, spacing: 12) {
                // Box — a small raised chip, so it catches the light like everything else
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.Color.checkboxBg)
                        .frame(width: 18, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(
                                    disabled
                                        ? Theme.Color.checkboxBorder.opacity(0.3)
                                        : Theme.Color.checkboxBorder,
                                    lineWidth: 1.5
                                )
                        )
                    if isOn && !disabled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.Color.timerText)
                    }
                }
                .diurnalElevation(disabled ? Theme.Elevation.flat : Theme.Elevation.input,
                                  cornerRadius: 3)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.custom(Theme.pixelFont, size: 8))
                        .foregroundColor(disabled
                            ? Theme.Color.timerText.opacity(0.3)
                            : Theme.Color.timerText)
                    Text(detail)
                        .font(.custom(Theme.pixelFont, size: 7))
                        .foregroundColor(Theme.Color.timerText.opacity(disabled ? 0.2 : 0.45))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .opacity(disabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
