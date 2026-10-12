import Foundation
import FamilyControls
import ManagedSettings

extension ManagedSettingsStore.Name {
    static let lightMinute = ManagedSettingsStore.Name("lightMinute")
}

/// A Screen Time shield over a user-chosen set of apps.
///
/// The shield lives in the system, not in this process: once applied it stays up
/// while Light Minute is backgrounded, suspended or killed, and only comes down
/// when something clears the store. That is the whole point of it — and also why
/// `clear()` has to be reachable from every path that ends the block.
@MainActor
final class AppBlocker: ObservableObject {

    /// `.unavailable` is not the same as `.denied`. Denied means the user saw
    /// Screen Time's prompt and said no — fixable in Settings. Unavailable means
    /// the prompt never came up: the build is not signed with the Family Controls
    /// entitlement, which Apple only grants to a paid developer account. Telling
    /// the two apart matters, because the advice for them is completely different.
    enum Access: Equatable { case notDetermined, granted, denied, unavailable }

    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var isShielding = false

    /// What the user picked. These are opaque tokens — the app never learns
    /// which apps they are, and they only mean anything on this device.
    @Published var selection: FamilyActivitySelection {
        didSet { Self.save(selection) }
    }

    private let store = ManagedSettingsStore(named: .lightMinute)

    private static let selectionKey = "lightminute.block.selection"
    private static let enabledKey   = "lightminute.block.enabled"

    init() {
        selection = Self.loadSelection()
        // The signed binary either carries the Family Controls entitlement or it
        // does not, and that is knowable at launch. Without it every request is
        // guaranteed to fail, so say so up front rather than making the user tap
        // into a prompt that will never appear.
        access = Diagnostics.hasFamilyControlsEntitlement == false
            ? .unavailable
            : Self.currentAccess()
        Diagnostics.record("launch", status: AuthorizationCenter.shared.authorizationStatus)
    }

    var isEmpty: Bool {
        selection.applicationTokens.isEmpty
            && selection.categoryTokens.isEmpty
            && selection.webDomainTokens.isEmpty
    }

    /// Everything picked, counted together — apps, whole categories and sites.
    var count: Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    // MARK: – Authorization

    /// Screen Time puts up its own prompt, so there is no usage-description
    /// string to write. On the Simulator this always fails: Family Controls
    /// needs a real device.
    ///
    /// A throw here is ambiguous on its own, so the status is what disambiguates
    /// it: if the user actually saw the prompt and refused, the system records
    /// `.denied`. If it still reads `.notDetermined` after a failure, no prompt
    /// was ever shown — the entitlement is missing and no amount of tapping in
    /// Settings will help.
    func requestAccess() async {
        Diagnostics.record("request.before", status: AuthorizationCenter.shared.authorizationStatus)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            access = .granted
            Diagnostics.record("request.ok", status: AuthorizationCenter.shared.authorizationStatus)
        } catch {
            switch Self.currentAccess() {
            case .granted: access = .granted
            case .denied:  access = .denied
            default:       access = .unavailable
            }
            Diagnostics.record("request.threw",
                               status: AuthorizationCenter.shared.authorizationStatus,
                               error: error)
        }
    }

    private static func currentAccess() -> Access {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved:      return .granted
        case .denied:        return .denied
        case .notDetermined: return .notDetermined
        @unknown default:    return .notDetermined
        }
    }

    // MARK: – The shield

    /// Idempotent: safe to call on every launch, foreground and finished session.
    func apply(blocked: Bool) {
        guard blocked, !isEmpty, access == .granted else { clear(); return }
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil : selection.webDomainTokens
        isShielding = true
    }

    func clear() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        isShielding = false
    }

    // MARK: – Persistence

    static func loadEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func saveEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: enabledKey)
    }

    private static func loadSelection() -> FamilyActivitySelection {
        guard let data = UserDefaults.standard.data(forKey: selectionKey),
              let decoded = try? JSONDecoder()
                  .decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return decoded
    }

    private static func save(_ selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        UserDefaults.standard.set(data, forKey: selectionKey)
    }
}

// MARK: – Diagnosis

/// Temporary instrumentation for one question: does Screen Time authorization
/// fail here because the entitlement is absent, or for some other reason?
/// Writes to the app's Documents directory so the file can be pulled off the
/// device with `devicectl`. Remove once the question is settled.
enum Diagnostics {

    private static let fileName = "screentime-diagnosis.txt"

    static var fileURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
    }

    static func record(_ event: String,
                       status: AuthorizationStatus,
                       error: Error? = nil) {
        var line = "[\(ISO8601DateFormatter().string(from: Date()))] \(event)"
        line += " | status=\(describe(status))"

        if let error {
            let ns = error as NSError
            line += " | errorType=\(type(of: error))"
            line += " | domain=\(ns.domain) code=\(ns.code)"
            line += " | desc=\(ns.localizedDescription)"
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                line += " | underlying=\(underlying.domain):\(underlying.code)"
            }
        }

        if event == "launch" {
            line += " | entitlementInBinary=\(hasFamilyControlsEntitlement.map(String.init) ?? "unknown")"
        }

        append(line)
    }

    private static func describe(_ status: AuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied:        return "denied"
        case .approved:      return "approved"
        @unknown default:    return "unknown(\(status.rawValue))"
        }
    }

    /// Reads the profile Xcode embedded at signing time. If `family-controls`
    /// is absent here, no runtime call can possibly succeed.
    ///
    /// `nil` means the profile could not be read at all — App Store builds have
    /// no embedded profile — so treat only an explicit `false` as proof.
    static var hasFamilyControlsEntitlement: Bool? {
        guard let url = Bundle.main.url(forResource: "embedded",
                                        withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1)
        else { return nil }
        return text.contains("com.apple.developer.family-controls")
    }

    private static func append(_ line: String) {
        guard let url = fileURL else { return }
        let entry = line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
