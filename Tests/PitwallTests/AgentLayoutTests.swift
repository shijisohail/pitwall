import Testing
import Foundation
@testable import Pitwall

@Suite struct AgentLayoutTests {
    let size = CGSize(width: 360, height: AgentLayout.height)

    private func run(_ id: String, zone: AgentZone, since: Date = .distantPast, state: AgentState = .working) -> AgentRun {
        var r = AgentRun(id: id, name: id); r.zone = zone; r.prevZone = zone; r.zoneSince = since; r.state = state
        return r
    }

    @Test func botsStayInsideTheirZoneWhileDrifting() {
        for z in [AgentZone.think, .read, .search, .edit, .run] {
            let rect = AgentLayout.zoneRect(z, in: size)
            for id in ["a", "agent-2", "zzz", "0mvwx"] {
                for t in stride(from: 0.0, to: 60.0, by: 3.7) {
                    let p = AgentLayout.anchor(z, id: id, restIndex: 0, t: t, in: size, origin: .zero)
                    #expect(rect.contains(p), "\(id) left \(z) at t=\(t): \(p)")
                }
            }
        }
    }

    @Test func positionsAreDeterministicAndDifferPerAgent() {
        let a = AgentLayout.anchor(.read, id: "a", restIndex: 0, t: 5, in: size, origin: .zero)
        #expect(a == AgentLayout.anchor(.read, id: "a", restIndex: 0, t: 5, in: size, origin: .zero))
        #expect(a != AgentLayout.anchor(.read, id: "b", restIndex: 0, t: 5, in: size, origin: .zero))
    }

    @Test func aGlideStartsAtTheOldZoneAndEndsInTheNewOne() {
        let now = Date()
        var r = run("a", zone: .run, since: now); r.prevZone = .read
        let start = AgentLayout.positions([r], now: now, animate: true, in: size)["a"]!
        let from = AgentLayout.anchor(.read, id: "a", restIndex: 0, t: now.timeIntervalSinceReferenceDate, in: size, origin: .zero)
        #expect(abs(start.x - from.x) < 0.5 && abs(start.y - from.y) < 0.5)
        r.zoneSince = now.addingTimeInterval(-AgentLayout.glide - 0.1)
        let end = AgentLayout.positions([r], now: now, animate: true, in: size)["a"]!
        #expect(AgentLayout.zoneRect(.run, in: size).contains(end))
    }

    @Test func aNewBotSpringsFromItsParent() {
        let now = Date()
        let parent = run("p", zone: .think)
        var child = run("c", zone: .read, since: now); child.prevZone = .hub; child.parentID = "p"
        let pos = AgentLayout.positions([parent, child], now: now, animate: true, in: size)
        #expect(abs(pos["c"]!.x - pos["p"]!.x) < 0.5 && abs(pos["c"]!.y - pos["p"]!.y) < 0.5)
    }

    @Test func finishedBotsLineUpInTheRestStripInFinishOrder() {
        var a = run("a", zone: .rest, state: .done); a.finishOrder = 2
        var b = run("b", zone: .rest, state: .done); b.finishOrder = 1
        let p = AgentLayout.positions([a, b], now: Date(), animate: false, in: size)
        #expect(p["b"]!.x < p["a"]!.x)
        #expect(AgentLayout.zoneRect(.rest, in: size).contains(p["a"]!))
    }

    @Test func animationOnlyRunsWhenSomethingIsMoving() {
        #expect(!AgentLayout.needsAnimation([run("a", zone: .rest, state: .done)]))
        #expect(AgentLayout.needsAnimation([run("a", zone: .read)]))
        #expect(AgentLayout.needsAnimation([run("a", zone: .rest, since: Date(), state: .done)]))
    }
}
