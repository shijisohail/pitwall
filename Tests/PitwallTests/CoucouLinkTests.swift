import Testing
import Foundation
@testable import Pitwall

/// Pitwall <-> Coucou: the request Pitwall relays, Coucou's native replies, and what Pitwall does with them.
@Suite struct CoucouLinkTests {
    private func object(_ d: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:] }

    @Test func aPermissionRequestIsRelayedInCoucousHookShape() {
        let data = CoucouLink.payload(requestID: "r1", tool: "Bash", input: ["command": "ls"], suggestions: [["type": "addRules"]],
                                      session: "s1", cwd: "/tmp/p")
        let o = object(data)
        #expect(data.last == 10)
        #expect(o["hook_event_name"] as? String == "PermissionRequest")
        #expect(o["tool_name"] as? String == "Bash")
        #expect(o["session_id"] as? String == "s1")
        #expect(o["bundle_id"] as? String == "io.github.shijisohail.pitwall")
        #expect(o["pitwall_link"] as? Bool == true)
        #expect((o["permission_suggestions"] as? [[String: Any]])?.count == 1)
        #expect(o["coucou_kind"] == nil)
    }

    @Test func aQuestionUsesCoucousDedicatedKind() {
        let o = object(CoucouLink.payload(requestID: "r2", tool: "AskUserQuestion", input: ["questions": []], suggestions: [],
                                          session: nil, cwd: "/tmp"))
        #expect(o["hook_event_name"] as? String == "PreToolUse")
        #expect(o["coucou_kind"] as? String == "ask_user_question")
        #expect(o["session_id"] as? String == "pitwall-r2")
    }

    @Test func coucousRepliesAreUnderstood() {
        func reply(_ s: String) -> CoucouLink.Reply? { CoucouLink.parseReply(Data(s.utf8)) }
        #expect(reply(#"{"permissionDecision":"allow"}"#) == .allow)
        #expect(reply(#"{"permissionDecision":"always"}"#) == .always)
        #expect(reply(#"{"permissionDecision":"deny"}"#) == .deny)
        #expect(reply(#"{"permissionDecision":"ask"}"#) == .ask)
        #expect(reply(#"{"permissionDecision":"allow","mode":"auto"}"#) == .plan(mode: "auto"))
        #expect(reply(#"{"permissionDecision":"change_plan"}"#) == .changePlan)
        #expect(reply(#"{"permissionDecision":"answer","answers":{"Q?":"Red","M?":["A","B"]}}"#) == .answers(["Q?": "Red", "M?": "A, B"]))
        #expect(reply("not json") == nil)
        #expect(reply(#"{"permissionDecision":"surprise"}"#) == nil)
    }

    @Test func repliesBecomeDecisions() {
        let input: [String: Any] = ["command": "ls", "questions": [["question": "Q?"]]]
        let sugg: [[String: Any]] = [["type": "addRules", "behavior": "allow"], ["type": "setMode", "mode": "acceptEdits"]]
        #expect(CoucouLink.decision(for: .ask, input: input, suggestions: sugg) == nil)
        #expect(CoucouLink.decision(for: .allow, input: input, suggestions: sugg)?.allow == true)
        #expect(CoucouLink.decision(for: .allow, input: input, suggestions: sugg)?.remember == nil)
        #expect(CoucouLink.decision(for: .always, input: input, suggestions: sugg)?.remember?["type"] as? String == "addRules")
        let deny = CoucouLink.decision(for: .deny, input: input, suggestions: sugg)
        #expect(deny?.allow == false && deny?.message == "Denied from Coucou")
        let answered = CoucouLink.decision(for: .answers(["Q?": "Red"]), input: input, suggestions: [])
        #expect((answered?.input?["answers"] as? [String: String])?["Q?"] == "Red")
        #expect(answered?.input?["command"] as? String == "ls")        // the original input is kept
        let plan = CoucouLink.decision(for: .plan(mode: "auto"), input: input, suggestions: [])
        #expect(plan?.remember?["type"] as? String == "setMode" && plan?.remember?["mode"] as? String == "auto")
        #expect(CoucouLink.decision(for: .changePlan, input: input, suggestions: [])?.allow == false)
    }

    @Test func noCoucouMeansNothingToWaitFor() {
        let none = CoucouLink.forward(Data("{}\n".utf8), path: "/tmp/pitwall-no-such-socket-\(UUID().uuidString)") { _ in }
        #expect(none == nil)
    }
}
