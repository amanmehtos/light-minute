import Foundation
import LightKit

/// The calls Light Minute makes against a Light Week account.
///
/// Not `LightKit.LightWeekClient`, which is otherwise this exact request.
/// Two things differ and both matter here. That one mints an op id inside
/// `log()`, so a retried push would arrive carrying a *new* id and be stored a
/// second time — `/sync` is idempotent on the op id, which only helps if the id
/// is decided once, when the session is queued, and kept for every attempt
/// after. And it holds one fixed token, where an outbox entry can easily sit
/// unsent for longer than an access token lives, so the token has to be asked
/// for per attempt instead.
///
/// Everything about the *format* — ids, the clock, the op and the entity — is
/// still LightKit's. Those are the parts that have to match the server byte for
/// byte, and a second implementation of them is exactly what LightKit exists to
/// prevent.
struct LightWeekClient {

    enum Failure: Error, LocalizedError {
        case http(status: Int, body: String)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .http(let status, let body):
                return status == 403
                    ? "This connection is read-only — reconnect to let Light Minute write."
                    : "Light Week returned \(status): \(body)"
            case .transport(let error):
                return error.localizedDescription
            }
        }
    }

    private let token: @Sendable () async throws -> String

    init(token: @escaping @Sendable () async throws -> String) {
        self.token = token
    }

    /// Whose account this is. Read once after connecting, so Settings can name
    /// the account without a round trip every time it opens.
    func accountEmail() async throws -> String? {
        struct Me: Decodable { let email: String? }
        let data = try await send("GET", "account/me")
        return try JSONDecoder().decode(Me.self, from: data).email
    }

    /// Hands ops to the account's log.
    ///
    /// `since` is the cursor already seen, so the response carries only what has
    /// happened elsewhere since then. Light Minute keeps no replica and ignores
    /// those ops apart from letting them advance the clock — but sending `0`
    /// would have the server return the whole account on every push.
    func push(_ ops: [Op], since: Int) async throws -> SyncResponse {
        let data = try await send("POST", "sync",
                                  body: try JSONEncoder().encode(Push(since: since, ops: ops)))
        return try JSONDecoder().decode(SyncResponse.self, from: data)
    }

    /// The push body.
    ///
    /// LightKit has `PushRequest` for this, but as a `public struct` whose
    /// memberwise initialiser stays internal — so it can be decoded outside the
    /// package and not built. Three fields are cheaper to spell out than a
    /// patch to a package two apps depend on; the ops inside them, which are
    /// the part that has to match the server exactly, are still LightKit's.
    private struct Push: Encodable {
        let version = lightWeekProtocolVersion
        let since: Int
        let ops: [Op]
    }

    private func send(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: LightWeek.origin.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await Self.perform(request)
    }

    /// Shared with the token endpoint, which is the one call that carries no
    /// bearer token of its own.
    static func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.http(status: http.statusCode,
                               body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}

/// This device, as the sync log knows it.
///
/// `n` plus ten characters, stable for the life of the install: it breaks clock
/// ties between devices and is how Light Week tells its own echo from a real
/// change. Not a secret and not worth the Keychain — losing it would only cost
/// a new identity, not access to anything.
enum LightWeekNode {
    private static let key = "lightminute.lightweek.node"

    static let id: String = {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty { return existing }
        let fresh = LightID.newNode()
        defaults.set(fresh, forKey: key)
        return fresh
    }()
}
