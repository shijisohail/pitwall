import Testing
import Foundation
@testable import Pitwall

@Suite struct ParallelLimitsTests {
    @Test func pressureWarnsFromEightyPercentAndIsFullAtTheLimit() {
        #expect(ParallelLimits.pressure(running: 15, limit: 20) == .ok)
        #expect(ParallelLimits.pressure(running: 16, limit: 20) == .near)
        #expect(ParallelLimits.pressure(running: 19, limit: 20) == .near)
        #expect(ParallelLimits.pressure(running: 20, limit: 20) == .full)
        #expect(ParallelLimits.pressure(running: 25, limit: 20) == .full)
        #expect(ParallelLimits.pressure(running: 5, limit: 0) == .ok)
    }

    @Test func settingsFileBeatsTheEnvironmentWhichBeatsTheDefault() {
        let k = ParallelLimits.subagentsKey
        #expect(ParallelLimits.limit(k, default: 20, settingsEnv: [:], processEnv: [:]) == 20)
        #expect(ParallelLimits.limit(k, default: 20, settingsEnv: [:], processEnv: [k: "8"]) == 8)
        #expect(ParallelLimits.limit(k, default: 20, settingsEnv: [k: "5"], processEnv: [k: "8"]) == 5)
        #expect(ParallelLimits.limit(k, default: 20, settingsEnv: [k: "0"], processEnv: [k: "abc"]) == 20)     // junk means unset
        #expect(ParallelLimits.limit(k, default: 20, settingsEnv: [k: "-3"], processEnv: [:]) == 20)
    }

    @Test func theEnvBlockOfASettingsFileIsReadAsStrings() {
        let json = #"{"model":"opus","env":{"CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS":"6","N":7,"X":true}}"#
        let env = ParallelLimits.settingsEnv(fromJSON: Data(json.utf8))
        #expect(env["CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"] == "6" && env["N"] == "7" && env["X"] == nil)
        #expect(ParallelLimits.settingsEnv(fromJSON: Data("not json".utf8)).isEmpty)
        #expect(ParallelLimits.settingsEnv(fromJSON: nil).isEmpty)
    }
}
