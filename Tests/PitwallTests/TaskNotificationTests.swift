import Testing
import Foundation
@testable import Pitwall

@Suite struct TaskNotificationTests {
    static let sample = """
    <task-notification>
    <task-id>a5b4c3</task-id>
    <output-file>/private/tmp/x/a5b4c3.output</output-file>
    <status>completed</status>
    <summary>Agent "Review core docs 794 760 (placeholder check)" finished</summary>
    <usage><subagent_tokens>27701</subagent_tokens><tool_uses>5</tool_uses><duration_ms>53079</duration_ms></usage>
    </task-notification>
    """

    @Test func parsesAFinishedAgent() throws {
        let (notes, rest) = TaskNotification.split(Self.sample)
        let n = try #require(notes.first)
        #expect(notes.count == 1 && rest.isEmpty)
        #expect(n.status == "completed" && n.taskID == "a5b4c3")
        #expect(n.title == "Agent \"Review core docs 794 760 (placeholder check)\" finished")
        #expect(n.detail == "53s · 5 tools · 27.7k tokens")
        #expect(n.outputFile == "/private/tmp/x/a5b4c3.output")
    }

    @Test func plainTextIsLeftAlone() {
        let (notes, rest) = TaskNotification.split("fix the login bug")
        #expect(notes.isEmpty && rest == "fix the login bug")
    }

    @Test func keepsTextAroundAndFindsSeveral() {
        let (notes, rest) = TaskNotification.split("before\n" + Self.sample + "\n" + Self.sample + "\nafter")
        #expect(notes.count == 2)
        #expect(rest.contains("before") && rest.contains("after") && !rest.contains("task-id"))
    }

    @Test func anUnterminatedBlockIsNotSwallowed() {
        let (notes, rest) = TaskNotification.split("hi <task-notification><status>x")
        #expect(notes.isEmpty && rest.contains("hi"))
    }

    @Test func formatsLongDurationsAndMissingFields() {
        let (n, _) = TaskNotification.split("<task-notification><status>failed</status><usage><duration_ms>125000</duration_ms><tool_uses>1</tool_uses></usage></task-notification>")
        #expect(n[0].detail == "2m 5s · 1 tool")
        #expect(n[0].title == "Background agent failed")
    }
}
