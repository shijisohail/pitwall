import Foundation
import AppKit

enum Role: String, Codable { case user, assistant }

enum Limits {
    /// One huge tool result (a big file read, a build log) must not balloon memory for every open session.
    static let toolResult = 100_000

    static func clip(_ s: String, to limit: Int = toolResult) -> String {
        guard s.utf8.count > limit else { return s }
        return String(s.prefix(limit)) + "\n… [truncated \(s.count - limit) more characters]"
    }
}

struct Block: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case text, thinking, tool, error, notice, output, local, image }
    var id = UUID().uuidString
    var kind: Kind
    var text = ""
    var toolID = ""
    var toolName = ""          // tool name, or the command label for .output / .local
    var inputJSON = ""
    var result: String? = nil
    var isError = false
    var imageData: Data? = nil
    var live: Bool? = nil          // a `!` command that is still running

    var input: [String: Any] {
        guard let d = inputJSON.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var role: Role
    var blocks: [Block] = []
    var apiID: String? = nil
    var date = Date()
}

/// Claude Code's permission modes. `flag` is the CLI spelling, `control` what set_permission_mode expects.
enum PermissionMode: String, CaseIterable, Identifiable {
    case manual, acceptEdits, plan, auto, dontAsk, bypassPermissions
    var id: String { rawValue }
    var flag: String { rawValue }
    var control: String { self == .manual ? "default" : rawValue }
    var label: String {
        switch self {
        case .manual: "Ask first"
        case .acceptEdits: "Auto-edit"
        case .plan: "Plan"
        case .auto: "Auto"
        case .dontAsk: "Don't ask"
        case .bypassPermissions: "Full access"
        }
    }
    var icon: String {
        switch self {
        case .manual: "hand.raised"
        case .acceptEdits: "pencil.line"
        case .plan: "map"
        case .auto: "wand.and.sparkles"
        case .dontAsk: "nosign"
        case .bypassPermissions: "bolt.shield"
        }
    }
    var blurb: String {
        switch self {
        case .manual: "Asks before edits and commands"
        case .acceptEdits: "Edits files freely, asks for commands"
        case .plan: "Read-only; proposes a plan first"
        case .auto: "A classifier approves safe actions"
        case .dontAsk: "Denies anything that would prompt"
        case .bypassPermissions: "No permission checks at all"
        }
    }
}

// MARK: Catalog (from the CLI's `initialize` response)

struct SlashCommand: Identifiable, Hashable {
    var name: String
    var description: String
    var hint = ""
    var native = false
    var id: String { name }
}

struct ModelInfo: Identifiable, Hashable {
    var value: String
    var name: String
    var detail: String
    var supportsEffort: Bool
    var levels: [String]
    var id: String { value }
}

struct Catalog {
    var commands: [SlashCommand] = []
    var models: [ModelInfo] = []
    var styles: [String] = []
    var version = ""
    var account: [String: String] = [:]

    init() {}
    init(_ b: [String: Any]) {
        commands = (b["commands"] as? [[String: Any]] ?? []).map {
            SlashCommand(name: $0["name"] as? String ?? "", description: $0["description"] as? String ?? "",
                         hint: $0["argumentHint"] as? String ?? "")
        }
        models = (b["models"] as? [[String: Any]] ?? []).map {
            ModelInfo(value: $0["value"] as? String ?? "", name: $0["displayName"] as? String ?? "",
                      detail: $0["description"] as? String ?? "",
                      supportsEffort: $0["supportsEffort"] as? Bool ?? false,
                      levels: $0["supportedEffortLevels"] as? [String] ?? [])
        }
        styles = b["available_output_styles"] as? [String] ?? []
        version = b["claude_code_version"] as? String ?? ""
        if let a = b["account"] as? [String: Any] {
            account = a.compactMapValues { v in (v as? String) ?? (v as? Bool).map { $0 ? "yes" : "no" } }
        }
    }
}

struct Usage {
    var fiveHour: Double
    var sevenDay: Double
    var fiveReset: Date?
    var sevenReset: Date?
}

struct QueuedMessage: Identifiable {
    let id = UUID()
    var text: String
    var images: [NSImage] = []
}

// MARK: Pending approvals (control_request can_use_tool)

struct Approval: Identifiable {
    enum Kind { case tool, question, plan }
    let id: String
    var kind: Kind
    var tool: String
    var input: [String: Any]
    var detail: String?
    var reason: String?
    var suggestions: [[String: Any]]
}
