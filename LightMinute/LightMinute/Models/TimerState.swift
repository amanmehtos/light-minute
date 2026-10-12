import Foundation

enum TimerMode { case focus, shortRest, longRest }
enum TimerStatus { case idle, running, paused }

struct TimerSettings {
    var focusDuration: TimeInterval      = 25 * 60
    var shortRestDuration: TimeInterval  = 5  * 60
    var longRestDuration: TimeInterval   = 20 * 60
    var sessions: Int  = 4

    // Target — focus sessions to finish today
    var dailyTarget: Int = 8

    // Block — shield the chosen apps until the target is met
    var blockApps: Bool = false

    // Focus Mode — on by default
    var flowModoro: Bool = true    // allow overflow / flow state
    var flowBreaks: Bool = true    // proportional rest (requires flowModoro)

    // End-of-session alert. No longer user-facing: a timer that ends silently is
    // broken, so sound and haptics are simply always on and the screen flash —
    // the most intrusive of the three — is off.
    let soundOn: Bool = true
    let vibrate: Bool = true
    let flash: Bool   = false

    // Interface — moonlight is the default look
    var darkMode: Bool  = true
    var flipFocus: Bool = true     // start on face-down, pause on face-up
}

/// Focus sessions finished today. Resets on its own when the date rolls over —
/// the target is a single day's, and yesterday's count is not carried forward.
struct DailyProgress {
    var day: Date       // start of the day the count belongs to
    var completed: Int

    private static let dayKey    = "lightminute.progress.day"
    private static let countKey  = "lightminute.progress.count"
    private static let targetKey = "lightminute.progress.target"

    /// The target outlives the day it was set on.
    static func loadTarget() -> Int? {
        let stored = UserDefaults.standard.integer(forKey: targetKey)
        return stored > 0 ? stored : nil
    }

    static func saveTarget(_ value: Int) {
        UserDefaults.standard.set(value, forKey: targetKey)
    }

    static func load(now: Date = Date(), calendar: Calendar = .current) -> DailyProgress {
        let today = calendar.startOfDay(for: now)
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: dayKey) as? Date
        guard let stored, calendar.isDate(stored, inSameDayAs: today) else {
            return DailyProgress(day: today, completed: 0)
        }
        return DailyProgress(day: today, completed: defaults.integer(forKey: countKey))
    }

    func save() {
        UserDefaults.standard.set(day, forKey: Self.dayKey)
        UserDefaults.standard.set(completed, forKey: Self.countKey)
    }

    /// Rolls the count over if midnight has passed since it was last touched.
    mutating func refresh(now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        if !calendar.isDate(day, inSameDayAs: today) {
            day = today
            completed = 0
            save()
        }
    }

    mutating func increment() {
        refresh()
        completed += 1
        save()
    }
}
