import Foundation

/// The Light Week task a timer is counting against.
///
/// Everything the screen needs to say arrives in the link, so opening a task in
/// Light Week and focusing on it here never waits on a round trip — or on being
/// signed in at all. Only `id` means anything to the server; the title and
/// project are carried so it is obvious on screen what is being counted.
///
/// Deliberately not persisted. The timer itself does not survive a relaunch, so
/// a binding that did would outlive the session it belongs to and start filing
/// someone's next hour under a task they have forgotten about.
struct BoundTask: Equatable {
    let id: String
    let projectId: String?
    let title: String
    let projectName: String?
    /// What Light Week suggested the timer be set to, when it said. Advice for
    /// this one session, not a change to the user's own focus length.
    let plannedSeconds: Int?

    /// Reads `com.lightminute.app:/focus?taskId=…&title=…&projectName=…&planned=1500`.
    ///
    /// RFC 8252's single-slash form has no host, so the verb lands in the path.
    /// The two-slash form, where it lands in the host instead, is read too: it
    /// is the spelling everyone reaches for first, and refusing it would look
    /// to the user like the link had simply failed.
    init?(focusURL url: URL) {
        guard url.scheme == LightWeek.urlScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let host = components.host ?? ""
        let path = components.path.hasPrefix("/")
            ? String(components.path.dropFirst())
            : components.path
        guard (host.isEmpty ? path : host) == "focus" else { return nil }

        let query = components.queryItems ?? []
        func value(_ name: String) -> String? {
            let found = query.first { $0.name == name }?.value
            return (found?.isEmpty == false) ? found : nil
        }

        guard let id = value("taskId") else { return nil }
        self.id = id
        self.projectId = value("projectId")
        // A link with no title still binds — the id is what the recording needs,
        // and a nameless task on screen is better than a dropped link.
        self.title = value("title") ?? "Light Week task"
        self.projectName = value("projectName")
        self.plannedSeconds = value("planned").flatMap(Int.init).map { max(60, $0) }
    }
}
