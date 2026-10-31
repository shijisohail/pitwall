import Foundation
import CoreGraphics

/// Where each bot stands on the Agents canvas. Pure functions of (agent, time, canvas size) so they can be tested
/// without any UI: a bot sits in the zone for what it is doing, drifts gently around a base spot there, and glides
/// to its new zone (eased) when that changes. Finished bots line up in the rest strip.
enum AgentLayout {
    static let height: CGFloat = 300
    static let glide: TimeInterval = 0.9

    static func zoneRect(_ z: AgentZone, in s: CGSize) -> CGRect {
        func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
            CGRect(x: x * s.width, y: y * s.height, width: w * s.width, height: h * s.height)
        }
        switch z {
        case .think: return r(0.00, 0.00, 0.32, 0.34)
        case .read: return r(0.34, 0.00, 0.32, 0.34)
        case .search: return r(0.68, 0.00, 0.32, 0.34)
        case .edit: return r(0.00, 0.54, 0.49, 0.30)
        case .run: return r(0.51, 0.54, 0.49, 0.30)
        case .rest: return r(0.00, 0.87, 1.00, 0.13)
        case .hub: return r(0.40, 0.37, 0.20, 0.14)
        }
    }

    static func hub(in s: CGSize) -> CGPoint {
        let r = zoneRect(.hub, in: s); return CGPoint(x: r.midX, y: r.midY)
    }

    /// Stable pseudo-random numbers per agent id (FNV-1a), so a bot's spot and drift never change between frames.
    private static func seed(_ id: String) -> (u: Double, v: Double, fx: Double, fy: Double, px: Double, py: Double) {
        var h: UInt64 = 0xcbf29ce484222325
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        func next() -> Double { h = h &* 6364136223846793005 &+ 1442695040888963407; return Double(h >> 33) / Double(1 << 31) }
        return (0.12 + 0.76 * next(), 0.12 + 0.76 * next(), 0.35 + 0.35 * next(), 0.30 + 0.35 * next(), next() * 6.28, next() * 6.28)
    }

    /// The spot for `run` in zone `z` at time `t` (seconds). `restIndex` orders finished bots along the rest strip.
    static func anchor(_ z: AgentZone, id: String, restIndex: Int, t: Double, in s: CGSize, origin: CGPoint) -> CGPoint {
        let k = seed(id)
        switch z {
        case .hub:
            return origin
        case .rest:
            let r = zoneRect(.rest, in: s)
            let step: CGFloat = 40
            return CGPoint(x: min(r.minX + 34 + CGFloat(restIndex) * step, r.maxX - 34), y: r.midY + 2 * sin(t * 0.8 + k.px))
        default:
            let r = zoneRect(z, in: s)
            let inner = CGRect(x: r.minX + 24, y: r.minY + 40, width: max(r.width - 48, 1), height: max(r.height - 56, 1))
            let ax = min(14, inner.width * 0.2), ay = min(9, inner.height * 0.2)
            // Kept clear of the canvas edges so a bot's speech bubble (about 100pt wide) is never cut off.
            let x = inner.minX + inner.width * k.u + ax * sin(t * k.fx + k.px)
            return CGPoint(x: min(max(x, 54), max(s.width - 54, 54)),
                           y: inner.minY + inner.height * k.v + ay * sin(t * k.fy + k.py))
        }
    }

    static func ease(_ p: Double) -> Double { let c = min(max(p, 0), 1); return c * c * (3 - 2 * c) }

    /// Positions for every agent. Parents come before children in `agents`, so a spawning bot can start from its
    /// parent's spot (or Claude's hub). With `animate` off, bots stand still exactly in their zones.
    static func positions(_ agents: [AgentRun], now: Date, animate: Bool, in s: CGSize) -> [String: CGPoint] {
        let t = animate ? now.timeIntervalSinceReferenceDate : 0
        let rest = agents.filter { $0.state.isFinished }.sorted { $0.finishOrder < $1.finishOrder }
        var restIndex: [String: Int] = [:]
        for (i, a) in rest.enumerated() { restIndex[a.id] = i }
        var out: [String: CGPoint] = [:]
        for a in agents {
            let origin = a.parentID.flatMap { out[$0] } ?? hub(in: s)
            let to = anchor(a.zone, id: a.id, restIndex: restIndex[a.id] ?? 0, t: t, in: s, origin: origin)
            let progress = animate ? ease(now.timeIntervalSince(a.zoneSince) / glide) : 1
            if progress >= 1 { out[a.id] = to; continue }
            let from = anchor(a.prevZone, id: a.id, restIndex: restIndex[a.id] ?? 0, t: t, in: s, origin: origin)
            out[a.id] = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
        }
        return out
    }

    /// True while anything is still moving, so the canvas only animates when there is something to see.
    static func needsAnimation(_ agents: [AgentRun], now: Date = Date()) -> Bool {
        agents.contains { !$0.state.isFinished || now.timeIntervalSince($0.zoneSince) < glide + 0.2 }
    }
}
