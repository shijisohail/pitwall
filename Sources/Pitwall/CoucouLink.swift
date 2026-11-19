import Foundation

/// Lets Coucou (the notch companion app) answer Pitwall's permission requests and questions.
///
/// Claude Code sessions that Pitwall runs ask for permission over Pitwall's own stdin protocol (`--permission-prompt-tool
/// stdio`). Coucou's usual route, a Claude Code hook, cannot decide those: the CLI still asks Pitwall and Pitwall's answer
/// wins (verified). So Pitwall itself relays each request to Coucou's socket, the way Coucou's `nb-hook` does, and races
/// Coucou's answer against its own card: the first answer wins and the other side drops its card. If Coucou is not
/// running, or answers "ask", nothing changes: Pitwall's card decides.
enum CoucouLink {
    static let pitwallBundleID = "io.github.shijisohail.pitwall"

    /// `~/Library/Application Support/NotchBuddy/nb.sock`, where Coucou listens (`PITWALL_COUCOU_SOCK` overrides it).
    static var socketPath: String {
        if let env = ProcessInfo.processInfo.environment["PITWALL_COUCOU_SOCK"], !env.isEmpty { return env }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NotchBuddy/nb.sock").path
    }

    /// What Coucou says (its native reply, one JSON line).
    enum Reply: Equatable {
        case allow, always, deny
        /// Hand it back: Pitwall's own card decides.
        case ask
        /// Answers to an AskUserQuestion, keyed by the question text.
        case answers([String: String])
        /// Allow an ExitPlanMode, optionally switching the permission mode (`auto` / `default`) like the CLI's own plan dialog.
        case plan(mode: String?)
        /// Reject the plan: the user will type the change.
        case changePlan
    }

    /// What Pitwall does with it.
    struct Decision {
        var allow: Bool
        var input: [String: Any]?
        var remember: [String: Any]?
        var message: String?
    }

    /// The request in Coucou's hook shape: a PermissionRequest, or the dedicated question kind for AskUserQuestion.
    static func payload(requestID: String, tool: String, input: [String: Any], suggestions: [[String: Any]],
                        session: String?, cwd: String, bundleID: String = pitwallBundleID) -> Data {
        var o: [String: Any] = [
            "hook_event_name": tool == "AskUserQuestion" ? "PreToolUse" : "PermissionRequest",
            "session_id": session ?? "pitwall-\(requestID)", "cwd": cwd, "tool_name": tool, "tool_input": input,
            "bundle_id": bundleID, "term_program": "",
            // Tells Coucou this request comes from Pitwall itself, the only route that can decide it. The same prompt also
            // reaches Coucou's Claude Code hook (if installed), which cannot decide a Pitwall session, so Coucou ignores that copy.
            "pitwall_link": true,
        ]
        if tool == "AskUserQuestion" { o["coucou_kind"] = "ask_user_question" }
        else if !suggestions.isEmpty { o["permission_suggestions"] = suggestions }
        var data = (try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes])) ?? Data("{}".utf8)
        data.append(10)
        return data
    }

    static func parseReply(_ data: Data) -> Reply? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let d = o["permissionDecision"] as? String else { return nil }
        switch d {
        case "allow":
            if let m = o["mode"] as? String, m == "auto" || m == "default" { return .plan(mode: m) }
            return .allow
        case "always": return .always
        case "deny": return .deny
        case "ask": return .ask
        case "change_plan": return .changePlan
        case "answer":
            var answers: [String: String] = [:]
            for (k, v) in o["answers"] as? [String: Any] ?? [:] {
                if let s = v as? String { answers[k] = s }
                else if let arr = v as? [String] { answers[k] = arr.joined(separator: ", ") }
            }
            return .answers(answers)
        default: return nil
        }
    }

    /// nil for "ask": nothing to do.
    static func decision(for reply: Reply, input: [String: Any], suggestions: [[String: Any]]) -> Decision? {
        switch reply {
        case .ask: return nil
        case .allow: return Decision(allow: true)
        case .always: return Decision(allow: true, remember: suggestions.first)       // the rule Claude Code itself suggested
        case .deny: return Decision(allow: false, message: "Denied from Coucou")
        case .answers(let a):
            var merged = input
            merged["answers"] = a
            return Decision(allow: true, input: merged)
        case .plan(let mode):
            return Decision(allow: true, remember: mode.map { ["type": "setMode", "mode": $0, "destination": "session"] })
        case .changePlan:
            return Decision(allow: false, message: "The user wants to change the plan and will type the changes in Pitwall.")
        }
    }

    // MARK: Socket

    /// One request on the wire. `cancel()` (Pitwall's own card was answered first) makes Coucou drop its card.
    final class Pending: @unchecked Sendable {
        fileprivate let fd: Int32
        private let lock = NSLock()
        private var cancelled = false
        fileprivate init(fd: Int32) { self.fd = fd }

        func cancel() {
            lock.lock(); defer { lock.unlock() }
            guard !cancelled else { return }
            cancelled = true
            shutdown(fd, SHUT_RDWR)         // wakes the reader; the reader closes the descriptor
        }

        fileprivate var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }

    /// Sends `payload` to Coucou and calls `onReply` with its answer (from a background thread). nil when Coucou is not
    /// listening. The reply never arrives if Coucou drops the request or closes the connection.
    static func forward(_ payload: Data, path: String = socketPath, onReply: @escaping @Sendable (Reply) -> Void) -> Pending? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { close(fd); return nil }
        let pending = Pending(fd: fd)
        DispatchQueue.global(qos: .userInitiated).async {
            defer { close(fd) }
            let wrote = payload.withUnsafeBytes { raw -> Bool in
                var off = 0
                while off < payload.count {
                    let n = write(fd, raw.baseAddress! + off, payload.count - off)
                    if n <= 0 { return false }
                    off += n
                }
                return true
            }
            guard wrote else { return }
            var reply = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while !reply.contains(10) {
                let n = read(fd, &buf, buf.count)
                if n <= 0 { break }
                reply.append(buf, count: n)
            }
            guard !pending.isCancelled, let line = reply.split(separator: 10).first, let r = parseReply(Data(line)) else { return }
            onReply(r)
        }
        return pending
    }
}
