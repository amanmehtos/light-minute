import Foundation
import LightKit

/// Focus sessions waiting to reach Light Week.
///
/// A focus timer has to work on the subway, so a finished session is written
/// here first and pushed afterwards — on the next foreground or launch, or
/// immediately if there happens to be a network. Nothing the timer does waits
/// on the account.
///
/// Entries live until the server settles them, which is safe because a push is
/// idempotent on the op's id: an op that already arrived is reported accepted
/// and applied once. That only holds if the id is decided here, when the
/// session is queued, rather than at each attempt — so it is part of the entry
/// and not of the sending.
@MainActor
final class FocusOutbox: ObservableObject {

    /// How a session ended, in the timer's own terms. The outbox owns the
    /// mapping onto Light Week's vocabulary so the view model never has to know
    /// the wire format.
    enum Outcome { case completed, abandoned }

    struct Entry: Codable, Identifiable {
        /// The op id. Decided once and kept, which is what makes resending safe.
        let id: String
        let clock: String
        let session: FocusSession
    }

    @Published private(set) var pending: [Entry]
    @Published private(set) var lastError: String?

    private let auth: LightWeekAuth
    private let client: LightWeekClient
    private let clock: Clock
    private var cursor: Int
    private var isFlushing = false

    /// A queue that only grows is a leak. Two hundred sessions is well past a
    /// year of a full day's focus going unsent, so anything beyond it is a
    /// queue that is never going to drain, and the oldest leaves first.
    private static let capacity = 200

    private static let queueKey  = "lightminute.lightweek.outbox"
    private static let cursorKey = "lightminute.lightweek.cursor"
    private static let clockKey  = "lightminute.lightweek.clock"

    init(auth: LightWeekAuth) {
        self.auth = auth
        self.client = LightWeekClient(token: { [auth] in try await auth.accessToken() })

        let defaults = UserDefaults.standard
        // Only the tokens need the Keychain. A record of how long someone sat
        // still is not a credential, and keeping it beside the rest of the
        // app's state is one less thing behaving differently.
        self.pending = (defaults.data(forKey: Self.queueKey))
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        self.cursor = defaults.integer(forKey: Self.cursorKey)

        self.clock = Clock(node: LightWeekNode.id)
        // The clock has to keep rising across launches. Without this it would
        // restart at counter zero, and two sessions queued inside the same
        // millisecond either side of a relaunch would carry the same stamp with
        // the same node id to break the tie with.
        if let last = defaults.string(forKey: Self.clockKey),
           let stamp = HLC(encoded: last) {
            clock.observe(stamp)
        }
    }

    // MARK: – Queueing

    /// Records a finished session. Returns without doing anything when there is
    /// no account — a timer with no grant is a complete timer, and queueing for
    /// an account that may never exist would mean uploading months of history
    /// the moment someone first connected.
    func enqueue(
        mode: TimerMode,
        outcome: Outcome,
        task: BoundTask?,
        startedAt: Date,
        endedAt: Date,
        plannedSeconds: Int,
        focusedSeconds: Int,
        interruptions: Int
    ) {
        guard auth.isSignedIn else { return }

        let session = FocusSession(
            taskId: task?.id,
            projectId: task?.projectId,
            startedAt: startedAt,
            endedAt: endedAt,
            plannedSeconds: plannedSeconds,
            focusedSeconds: focusedSeconds,
            kind: Self.kind(of: mode),
            outcome: outcome == .completed ? .completed : .abandoned,
            interruptions: interruptions,
            source: "light-minute-ios")

        let stamp = clock.next()
        pending.append(Entry(id: LightID.new(), clock: stamp.encoded, session: session))
        if pending.count > Self.capacity { pending.removeFirst(pending.count - Self.capacity) }
        UserDefaults.standard.set(stamp.encoded, forKey: Self.clockKey)
        save()

        // `Task` is LightKit's entity type in this file, so the concurrency one
        // has to be named in full.
        _Concurrency.Task { await self.flush() }
    }

    /// Gives up the queue along with the grant. These recordings belong to the
    /// account that is being disconnected; holding them to maybe push at
    /// whoever signs in next would file someone else's focus under their name.
    func discard() {
        pending = []
        lastError = nil
        save()
    }

    // MARK: – Sending

    func flush() async {
        guard !isFlushing, !pending.isEmpty, auth.isSignedIn else { return }
        isFlushing = true
        defer { isFlushing = false }

        let batch = pending
        do {
            let ops = try batch.map { entry in
                Op(id: entry.id,
                   kind: "focusSession",
                   entityId: entry.session.id,
                   type: "upsert",
                   // A whole row rather than a patch, which is what a sparse
                   // patch means for an entity the server has never seen.
                   fields: try JSONValue.encoding(entry.session),
                   clock: entry.clock,
                   node: LightWeekNode.id)
            }

            let response = try await client.push(ops, since: cursor)
            cursor = response.cursor
            UserDefaults.standard.set(cursor, forKey: Self.cursorKey)

            // Whatever happened on other devices while this queue sat still has
            // to be absorbed, or the next session this device records could
            // carry a stamp that sorts before an edit it actually followed.
            for op in response.ops {
                if let remote = HLC(encoded: op.clock) { clock.observe(remote) }
            }
            // A fresh stamp, stored as a floor: it sorts after everything just
            // observed, so the next launch resumes above all of it.
            UserDefaults.standard.set(clock.next().encoded, forKey: Self.clockKey)

            // The server refuses only what it will never accept, so a rejected
            // op is as settled as an accepted one — just unhappily.
            let rejected = response.rejected ?? []
            let settled = Set((response.accepted ?? ops.map(\.id)) + rejected.map(\.id))
            pending.removeAll { settled.contains($0.id) }
            lastError = rejected.isEmpty
                ? nil
                : "Light Week refused \(rejected.count): \(rejected[0].reason)"
            save()
        } catch {
            // Everything stays queued. A 401 the refresh could not fix, a
            // read-only grant, a tunnel — none of them are reasons to throw
            // away the recording this queue exists to keep.
            lastError = error.localizedDescription
        }
    }

    // MARK: – Plumbing

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: Self.queueKey)
    }

    private static func kind(of mode: TimerMode) -> FocusSession.Kind {
        switch mode {
        case .focus:     return .focus
        case .shortRest: return .shortBreak
        case .longRest:  return .longBreak
        }
    }
}
