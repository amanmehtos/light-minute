import Foundation
import SwiftUI
import AudioToolbox
import CoreMotion
import UserNotifications

@MainActor
class TimerViewModel: ObservableObject {

    // MARK: – Published state
    @Published var mode: TimerMode     = .focus
    @Published var status: TimerStatus = .idle
    @Published var timeRemaining: TimeInterval = 25 * 60
    @Published var overflowTime: TimeInterval  = 0
    @Published var isOverflow: Bool   = false
    @Published var completedSessions: Int = 0
    @Published var settings = TimerSettings() { didSet { onSettingsChanged(oldValue) } }
    @Published var showSettings: Bool = false
    @Published var mikeMessage: String = "Turn over your device and focus!"
    @Published var mikeAngry: Bool = false
    @Published var flashScreen: Bool = false
    @Published private(set) var today = DailyProgress.load()

    // MARK: – Wall-clock timekeeping
    // The countdown is derived from real dates, never from accumulated ticks,
    // so suspending the app (or the ticker being throttled) can't lose time.
    private var modeDuration: TimeInterval = 25 * 60
    private var anchor: Date?                        // start of the running segment
    private var accumulated: TimeInterval = 0        // elapsed before this segment
    private var didSignalEnd = false

    private var elapsed: TimeInterval {
        accumulated + (anchor.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private var ticker: Timer?
    private var actualFocusTime: TimeInterval = 0
    private let liveActivity = RestLiveActivity()
    private let motion = CMMotionManager()
    private var lastFaceDown: Bool = false
    private static let restNotificationID = "lightminute.rest.end"

    // Feedback generators — pre-created and prepared
    private let impactLight  = UIImpactFeedbackGenerator(style: .light)
    private let impactHeavy  = UIImpactFeedbackGenerator(style: .heavy)
    private let notifGen     = UINotificationFeedbackGenerator()

    // MARK: – Derived
    var minutes: Int { isOverflow ? Int(overflowTime) / 60 : max(0, Int(timeRemaining) / 60) }
    var seconds: Int { isOverflow ? Int(overflowTime) % 60 : max(0, Int(timeRemaining) % 60) }
    var filledDots: Int { completedSessions % settings.sessions }
    var colorScheme: ColorScheme { settings.darkMode ? .dark : .light }

    var targetReached: Bool { today.completed >= settings.dailyTarget }

    /// 0…1 — how far into today's target we are.
    var targetFraction: Double {
        guard settings.dailyTarget > 0 else { return 0 }
        return min(1, Double(today.completed) / Double(settings.dailyTarget))
    }

    var currentModeDuration: TimeInterval { modeDuration }

    // MARK: – Lifecycle

    func onAppear() {
        impactLight.prepare()
        impactHeavy.prepare()
        notifGen.prepare()
        liveActivity.clearStale()
        settings.dailyTarget = DailyProgress.loadTarget() ?? settings.dailyTarget
        today.refresh()
        if settings.flipFocus { startFlipDetection() }
    }

    func onDisappear() {
        stopFlipDetection()
    }

    /// Re-derive the countdown after the app comes back from the background.
    func onForeground() {
        if status == .running { startTicker() }
        today.refresh()          // the app may have been away across midnight
        refresh()
    }

    func onBackground() {
        // Keep the anchor — `elapsed` stays correct — but drop the ticker.
        ticker?.invalidate(); ticker = nil
    }

    // MARK: – Controls

    func start() {
        if status == .idle && mode == .focus {
            modeDuration = settings.focusDuration
            accumulated  = 0
            didSignalEnd = false
            isOverflow   = false
            overflowTime = 0
        }
        status    = .running
        mikeAngry = false
        mikeMessage = focusMessages.randomElement()!
        vibrateStart()
        anchor = Date()
        startTicker()
        refresh()
    }

    func pause() {
        freezeClock()
        status = .paused
        stopTicker()
    }

    func reset() {
        stopTicker()
        liveActivity.stop()
        cancelRestNotification()
        anchor = nil; accumulated = 0; didSignalEnd = false
        status     = .idle
        mode       = .focus
        isOverflow = false; overflowTime = 0; actualFocusTime = 0
        modeDuration  = settings.focusDuration
        timeRemaining = settings.focusDuration
        mikeAngry = false
        mikeMessage = idleMessages.randomElement()!
        if settings.flipFocus { startFlipDetection() }
    }

    func skip() {
        switch mode {
        case .focus:
            actualFocusTime = elapsed
            beginRest()
        case .shortRest, .longRest:
            endRest()
        }
    }

    func takeRest() {
        actualFocusTime = max(elapsed, settings.focusDuration)
        beginRest()
    }

    func openSettings() {
        freezeClock()
        stopTicker()
        stopFlipDetection()
        if status == .running { status = .paused }
        showSettings = true
        mikeMessage = settingsMsgs.randomElement()!
    }

    func closeSettings() {
        showSettings = false
        if settings.flipFocus { startFlipDetection() }
    }

    // MARK: – Mode transitions

    private func beginRest() {
        stopTicker()
        isOverflow = false; overflowTime = 0
        completedSessions += 1

        // A finished focus block is what counts toward the day's target.
        let alreadyMet = targetReached
        today.increment()
        let justHitTarget = !alreadyMet && targetReached

        let long = completedSessions % settings.sessions == 0
        mode = long ? .longRest : .shortRest
        modeDuration  = proportionalRest(long: long)
        accumulated   = 0
        didSignalEnd  = false
        timeRemaining = modeDuration
        mikeMessage   = justHitTarget
            ? "That's \(settings.dailyTarget) today. Target met."
            : restMessages.randomElement()!
        status = .running
        anchor = Date()
        startTicker()

        let end = Date().addingTimeInterval(modeDuration)
        liveActivity.start(endDate: end,
                           total: modeDuration,
                           isLong: long,
                           sessionsDone: completedSessions,
                           sessionsTotal: settings.sessions)
        scheduleRestNotification(at: end, long: long)
    }

    private func endRest() {
        stopTicker()
        liveActivity.stop()
        cancelRestNotification()
        anchor = nil; accumulated = 0; didSignalEnd = false
        mode = .focus
        isOverflow = false; overflowTime = 0; actualFocusTime = 0
        modeDuration  = settings.focusDuration
        timeRemaining = settings.focusDuration
        status = .idle
        mikeMessage = backToFocusMsgs.randomElement()!
        if settings.flipFocus { startFlipDetection() }
    }

    // MARK: – Flip Focus

    /// Must be called even when idle — flip detection should work from idle state
    func startFlipDetection() {
        guard settings.flipFocus, motion.isDeviceMotionAvailable,
              !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.3
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let gz = data?.gravity.z else { return }
            let faceDown = gz > 0.6
            guard faceDown != self.lastFaceDown else { return }
            self.lastFaceDown = faceDown

            if faceDown {
                // Phone face-down → start timer from any non-running focus state
                if self.mode == .focus && self.status != .running && !self.showSettings {
                    self.start()
                }
            } else {
                // Phone face-up → pause if running
                if self.mode == .focus && self.status == .running {
                    self.pause()
                    self.mikeAngry = true
                    self.mikeMessage = self.angryMessages.randomElement()!
                }
            }
        }
    }

    func stopFlipDetection() {
        motion.stopDeviceMotionUpdates()
    }

    private func onSettingsChanged(_ old: TimerSettings) {
        // Flip Focus toggled on → start detection immediately
        if settings.flipFocus && !old.flipFocus { startFlipDetection() }
        if !settings.flipFocus && old.flipFocus { stopFlipDetection() }
        // Focus length edited while idle → reflect it on the dial
        if settings.focusDuration != old.focusDuration,
           mode == .focus, status == .idle {
            modeDuration  = settings.focusDuration
            timeRemaining = settings.focusDuration
        }
        if settings.dailyTarget != old.dailyTarget {
            DailyProgress.saveTarget(settings.dailyTarget)
        }
    }

    // MARK: – Clock

    private func freezeClock() {
        if let a = anchor {
            accumulated += Date().timeIntervalSince(a)
            anchor = nil
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate(); ticker = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func refresh() {
        guard status == .running else { return }
        let e = elapsed

        switch mode {
        case .focus:
            if e >= modeDuration {
                if settings.flowModoro {
                    if !didSignalEnd {
                        didSignalEnd = true
                        notifyEnd()
                        mikeMessage = overflowMessages.randomElement()!
                    }
                    isOverflow    = true
                    timeRemaining = 0
                    overflowTime  = e - modeDuration
                } else {
                    timeRemaining = 0
                    if !didSignalEnd { didSignalEnd = true; notifyEnd() }
                    actualFocusTime = modeDuration
                    beginRest()
                }
            } else {
                timeRemaining = modeDuration - e
                overflowTime  = 0
            }

        case .shortRest, .longRest:
            if e >= modeDuration {
                timeRemaining = 0
                if !didSignalEnd { didSignalEnd = true; notifyEnd() }
                endRest()
            } else {
                timeRemaining = modeDuration - e
            }
        }
    }

    // MARK: – Notifications (sound / vibrate / flash)

    private func vibrateStart() {
        guard settings.vibrate else { return }
        impactLight.prepare()
        impactLight.impactOccurred(intensity: 0.6)
    }

    private func notifyEnd() {
        if settings.soundOn  { playAlertSound() }
        if settings.vibrate  { vibrateEnd() }
        if settings.flash    { triggerFlash() }
    }

    private func playAlertSound() {
        AudioServicesPlayAlertSoundWithCompletion(1005, nil)
    }

    private func vibrateEnd() {
        notifGen.prepare()
        notifGen.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.notifGen.notificationOccurred(.success)
        }
    }

    private func triggerFlash() {
        let times: [TimeInterval] = [0, 0.18, 0.36]
        for t in times {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                self.flashScreen = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                    self.flashScreen = false
                }
            }
        }
    }

    /// Fires even if the app is suspended when the break runs out.
    /// Permission is requested here — the first time it is actually needed —
    /// rather than ambushing the user on launch.
    private func scheduleRestNotification(at date: Date, long: Bool) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = long ? "Long rest complete" : "Rest complete"
        content.body  = "Back to orbit, astronaut."
        if settings.soundOn { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: Self.restNotificationID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelRestNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.restNotificationID])
    }

    // MARK: – Proportional rest
    private func proportionalRest(long: Bool) -> TimeInterval {
        let base = long ? settings.longRestDuration : settings.shortRestDuration
        guard settings.flowModoro && settings.flowBreaks && actualFocusTime > 0 else { return base }
        let ratio = base / settings.focusDuration
        return max(60, (actualFocusTime * ratio).rounded())
    }

    // MARK: – Messages
    private let idleMessages      = ["Turn over your device and focus!", "Ready when you are, explorer.", "Set your target and launch!"]
    private let focusMessages     = ["Stay in orbit. No distractions!", "Mission in progress. Eyes forward.", "Locked in. Keep going."]
    private let overflowMessages  = ["You're in the FLOW STATE. Keep going!", "Beyond target — locked in!", "Flow state achieved. Rest when ready."]
    private let restMessages      = ["Rest earned! Proportional to your flow.", "Recharging... you earned this.", "Flow complete. Rest up, astronaut."]
    private let backToFocusMsgs   = ["Break's over. Back to orbit!", "Recharged. Ready for liftoff?", "Rest complete. Focus awaits."]
    private let settingsMsgs      = ["\"LONG BREAK\" is after all your sessions.", "Adjust your mission parameters here."]
    private let angryMessages     = ["Hey! You peeked! Face it down again!", "No cheating! Back to work!", "Eyes off! Put it face-down!", "Put it face-down and focus!"]
}
