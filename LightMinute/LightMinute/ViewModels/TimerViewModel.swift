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
    /// The Light Week task this focus block is being filed against, if any.
    @Published private(set) var boundTask: BoundTask?

    // MARK: – Light Week
    // Both optional, and inert with no account: the timer is a whole timer for
    // someone who never signs in, and nothing below is allowed to make it wait.
    let auth: LightWeekAuth
    let outbox: FocusOutbox

    init() {
        let auth = LightWeekAuth()
        self.auth = auth
        self.outbox = FocusOutbox(auth: auth)
    }

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
    /// When the current focus block began, as against `anchor`, which is only
    /// the start of the running segment and moves on every pause.
    private var sessionStart: Date?
    /// Times this block was stopped part-way. Not incremented on backgrounding,
    /// even though Light Week counts that as an interruption: with Flip Focus
    /// on, putting the phone face-down locks the screen, so every intended
    /// minute of focus would arrive looking like one.
    private var interruptions: Int = 0
    /// A length this one session was asked to run for by a Light Week link. The
    /// user's focus length is a setting; a link gets to say "this one is 45
    /// minutes" without rewriting it.
    private var linkedDuration: TimeInterval?
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

    /// What this stretch of time is being filed under, in one line.
    ///
    /// The bound Light Week task when there is one, because that is the whole
    /// point of binding it. Otherwise what the timer is doing — a header that
    /// goes blank when nothing is bound reads as broken rather than as idle.
    var focusLine: String {
        if let boundTask {
            let parts = [boundTask.projectName, boundTask.title].compactMap { $0 }
            return parts.joined(separator: " · ").uppercased()
        }
        switch mode {
        case .focus: return isOverflow ? "FLOW STATE" : "FOCUS"
        case .shortRest: return "SHORT REST"
        case .longRest: return "LONG REST"
        }
    }

    // MARK: – Lifecycle

    func onAppear() {
        impactLight.prepare()
        impactHeavy.prepare()
        notifGen.prepare()
        liveActivity.clearStale()
        settings.dailyTarget = DailyProgress.loadTarget() ?? settings.dailyTarget
        today.refresh()
        if settings.flipFocus { startFlipDetection() }
        flushOutbox()
    }

    func onDisappear() {
        stopFlipDetection()
    }

    /// Re-derive the countdown after the app comes back from the background.
    func onForeground() {
        if status == .running { startTicker() }
        today.refresh()          // the app may have been away across midnight
        refresh()
        flushOutbox()
    }

    func onBackground() {
        // Keep the anchor — `elapsed` stays correct — but drop the ticker.
        ticker?.invalidate(); ticker = nil
    }

    // MARK: – Controls

    func start() {
        if status == .idle && mode == .focus {
            modeDuration  = linkedDuration ?? settings.focusDuration
            accumulated   = 0
            didSignalEnd  = false
            isOverflow    = false
            overflowTime  = 0
            sessionStart  = Date()
            interruptions = 0
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
        // Before the evidence goes. A timer that records only its successes
        // produces statistics that flatter you, so a block given up part-way
        // through is written down as abandoned — and one that had already run
        // past its target as completed, because it had been.
        if mode == .focus, status != .idle {
            record(focused: elapsed,
                   outcome: elapsed >= modeDuration ? .completed : .abandoned)
        }
        liveActivity.stop()
        cancelRestNotification()
        anchor = nil; accumulated = 0; didSignalEnd = false
        sessionStart = nil; interruptions = 0
        status     = .idle
        mode       = .focus
        isOverflow = false; overflowTime = 0; actualFocusTime = 0
        modeDuration  = linkedDuration ?? settings.focusDuration
        timeRemaining = modeDuration
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

    // MARK: – Light Week

    /// A link from Light Week: `com.lightminute.app:/focus?taskId=…`.
    ///
    /// Binds the task it names so the next finished block is filed against it.
    /// Unknown links are ignored rather than complained about — the scheme is
    /// shared with the sign-in callback, and one day with whatever comes next.
    func open(_ url: URL) {
        guard let task = BoundTask(focusURL: url) else { return }
        boundTask      = task
        linkedDuration = task.plannedSeconds.map(TimeInterval.init)
        if mode == .focus, status == .idle {
            modeDuration  = linkedDuration ?? settings.focusDuration
            timeRemaining = modeDuration
        }
        if showSettings { closeSettings() }
        mikeMessage = boundMessages.randomElement()!
    }

    /// Stops counting against the task, without disturbing the timer.
    func unbind() {
        boundTask      = nil
        linkedDuration = nil
        if mode == .focus, status == .idle {
            modeDuration  = settings.focusDuration
            timeRemaining = modeDuration
        }
    }

    /// Disconnects the account and gives up anything still queued for it.
    func disconnectLightWeek() {
        auth.signOut()
        outbox.discard()
    }

    /// Hands a focus block to the outbox.
    ///
    /// Under a minute is a mis-tap rather than a session. The dial is adjusted
    /// in whole minutes and every adjustment calls `reset()`, so recording
    /// those would fill the account with noise instead of with the honest
    /// abandonments it is there to keep.
    private func record(focused: TimeInterval, outcome: FocusOutbox.Outcome) {
        guard focused >= 60 else { return }
        outbox.enqueue(
            mode: mode,
            outcome: outcome,
            task: boundTask,
            startedAt: sessionStart ?? Date().addingTimeInterval(-focused),
            endedAt: Date(),
            plannedSeconds: Int(modeDuration.rounded()),
            focusedSeconds: Int(focused.rounded()),
            interruptions: interruptions)
    }

    private func flushOutbox() {
        Task { await outbox.flush() }
    }

    // MARK: – Mode transitions

    private func beginRest() {
        stopTicker()
        isOverflow = false; overflowTime = 0
        completedSessions += 1

        // A finished focus block is what counts toward the day's target — and
        // what Light Week wants. `elapsed` rather than `actualFocusTime`: that
        // one is floored to the focus length for the sake of proportional rest,
        // and the gap between planned and spent is the interesting part here.
        record(focused: elapsed, outcome: .completed)
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
        sessionStart = nil; interruptions = 0
        modeDuration  = linkedDuration ?? settings.focusDuration
        timeRemaining = modeDuration
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
            // Setting it by hand is the last word on it, link or no link.
            linkedDuration = nil
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
            // Counted here rather than in `pause()` so that every way of
            // stopping a block mid-way counts the same: the pause control, a
            // face-up phone, opening settings. The time is excluded from the
            // recording in all three cases, and counting only one of them
            // would leave the two halves of the session disagreeing.
            if mode == .focus, status == .running { interruptions += 1 }
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
    private let boundMessages     = ["Target acquired. Face it down and go.", "Mission assigned. Ready when you are.", "Locked on. Let's log some time."]
    private let angryMessages     = ["Hey! You peeked! Face it down again!", "No cheating! Back to work!", "Eyes off! Put it face-down!", "Put it face-down and focus!"]
}
