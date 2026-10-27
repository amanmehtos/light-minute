import SwiftUI

struct ContentView: View {
    @ObservedObject var vm: TimerViewModel
    @StateObject private var sky = DiurnalSky()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if vm.showSettings {
                SettingsView(vm: vm)
            } else {
                TimerScreenView(vm: vm)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.showSettings)
        .animation(.easeInOut(duration: 0.3),  value: vm.mode == .focus)
        .preferredColorScheme(vm.colorScheme)
        // Every shadow in the app is cast by this one light.
        .environment(\.diurnalLight, sky.light)
        // Flash overlay
        .overlay(
            vm.flashScreen
                ? Color.white.ignoresSafeArea().allowsHitTesting(false)
                : nil
        )
        .onAppear {
            sky.isMoonlit = vm.settings.darkMode
            sky.start()
        }
        .onChange(of: vm.settings.darkMode) { _, dark in
            sky.isMoonlit = dark
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:     vm.onForeground(); sky.start()
            case .background: vm.onBackground(); sky.stop()
            default: break
            }
        }
    }
}

// MARK: – Timer screen (focus + rest share the same massive-timer layout)

struct TimerScreenView: View {
    @ObservedObject var vm: TimerViewModel

    // Approximate fixed heights of non-timer elements
    private let headerH:  CGFloat = 72   // MIKE is a line of text now, not a portrait
    private let labelH:   CGFloat = 20
    private let dotsH:    CGFloat = 36
    private let targetH:  CGFloat = 18   // today's count against the target
    private let dotGap:   CGFloat = 16   // gap between the readout and the buttons
    private let btnsH:    CGFloat = 52
    private let bottomPad:CGFloat = 44
    private let topSpacer:CGFloat = 8
    private let botSpacer:CGFloat = 0

    private var isResting: Bool { vm.mode != .focus }

    var body: some View {
        GeometryReader { geo in
            let screenW = geo.size.width
            let screenH = geo.size.height

            // Height available for the timer block
            let usedH = headerH + labelH + dotsH + targetH + dotGap + btnsH + bottomPad
                      + topSpacer + botSpacer
            let timerH = screenH - usedH
            let timerBox = CGSize(width: screenW - 16, height: timerH)
            let fSize = CGFloat.timerFontSize(in: timerBox)

            ZStack {
                Theme.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    MikeHeaderView(message: vm.mikeMessage,
                                   angry: vm.mikeAngry,
                                   task: vm.boundTask)
                        .frame(height: headerH, alignment: .top)

                    Spacer().frame(height: topSpacer)

                    // Mode / flow-state label
                    Group {
                        if vm.isOverflow {
                            Text("FLOW STATE")
                        } else if vm.mode == .shortRest {
                            Text("SHORT REST")
                        } else if vm.mode == .longRest {
                            Text("LONG REST")
                        } else {
                            Text(" ")   // placeholder keeps layout stable
                        }
                    }
                    .font(.custom(Theme.pixelFont, size: 8))
                    .foregroundColor(Theme.Color.timerText.opacity(0.45))
                    .frame(height: labelH)

                    // Timer — sized to fill remaining space
                    PixelTimerView(
                        minutes:   vm.minutes,
                        seconds:   vm.seconds,
                        isOutline: vm.isOverflow,
                        fontSize:  fSize
                    )
                    .frame(width: screenW - 16, height: timerH)
                    .padding(.horizontal, 8)

                    Spacer().frame(height: botSpacer)

                    SessionDotsView(
                        total:      vm.settings.sessions,
                        filled:     vm.filledDots,
                        extraCount: 0
                    )
                    .frame(height: dotsH)

                    // Today against the day's target. Brightens once it is met,
                    // and goes back to zero of its own accord at midnight.
                    Text("\(vm.today.completed) / \(vm.settings.dailyTarget) TODAY")
                        .font(.custom(Theme.pixelFont, size: 7))
                        .foregroundColor(Theme.Color.timerText
                            .opacity(vm.targetReached ? 0.8 : 0.35))
                        .frame(height: targetH)

                    Spacer().frame(height: dotGap)

                    controls
                        .frame(height: btnsH)
                        .padding(.bottom, bottomPad)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Tap-to-start only when flipFocus is OFF
                if !vm.settings.flipFocus && vm.mode == .focus && vm.status == .idle {
                    vm.start()
                }
            }
            .onAppear   { vm.onAppear() }
            .onDisappear { vm.onDisappear() }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var controls: some View {
        if isResting {
            HStack(spacing: 16) {
                PixelButton("Skip", icon: "forward.end.fill") { vm.skip() }
                iconBtn("slider.horizontal.3") { vm.openSettings() }
            }
        } else if vm.status == .idle {
            HStack(spacing: 16) {
                PixelButton("Start", icon: "play.fill") { vm.start() }
                iconBtn("slider.horizontal.3") { vm.openSettings() }
            }
        } else if vm.isOverflow {
            HStack(spacing: 12) {
                PixelButton("Rest", icon: "moon.fill") { vm.takeRest() }
                iconBtn("arrow.counterclockwise") { vm.reset() }
                iconBtn("slider.horizontal.3")   { vm.openSettings() }
            }
        } else {
            HStack(spacing: 16) {
                PixelButton("Reset", icon: "arrow.counterclockwise") { vm.reset() }
                iconBtn("slider.horizontal.3") { vm.openSettings() }
            }
        }
    }

    private func iconBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Color.buttonText)
                .frame(width: 46, height: 46)
                .background(Theme.Color.buttonBg)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

#Preview { ContentView(vm: TimerViewModel()) }
