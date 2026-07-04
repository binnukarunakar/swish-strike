import SwishStrikeCore
import Foundation

// SwishStrikeParity — replays the shared golden trace through the Swift engine and
// asserts it reproduces the JS-frozen expected output, scenario for scenario.
// This is the cross-language parity proof (closes the "two matching suites, not a
// shared fixture" gap). Exits non-zero on any divergence.
//
//   swift run SwishStrikeParity                       # default fixture path
//   swift run SwishStrikeParity /abs/path/golden.json # explicit path

// --- fixture schema (mirrors web-prototype/test/golden.fixtures.json) ---

struct Fixture: Codable { let scenarios: [Scenario] }
struct Scenario: Codable {
    let name: String
    let rule: RuleSpec
    let samples: [Smp]
    let expectedCount: Int
    let expectedEventTimes: [Double]
}
struct RuleSpec: Codable { let kind: String; let zone: ZoneSpec?; let opts: Opts? }
struct ZoneSpec: Codable { let left, top, right, bottom: Double }
struct Opts: Codable {
    let cooldown: Double?; let xTolerance: Double?; let armWindow: Double?
    let minAmplitude: Double?; let direction: String?
    let smoothingAlpha: Double?; let minConfidence: Double?; let maxGap: Double?
}
struct Smp: Codable { let t: Double; let x: Double?; let y: Double?; let c: Double? }

// --- build a CountRule from a spec, honoring the SAME defaults as the JS builders ---

func buildRule(_ s: RuleSpec) -> CountRule {
    let o = s.opts
    if s.kind == "zoneCrossDown" {
        let z = s.zone!
        return .zoneCrossDown(Zone(left: z.left, top: z.top, right: z.right, bottom: z.bottom),
                              xTolerance: o?.xTolerance ?? 0.05,
                              armWindow: o?.armWindow ?? 1.5,
                              cooldown: o?.cooldown ?? 1.0,
                              smoothingAlpha: o?.smoothingAlpha ?? 0.5,
                              minConfidence: o?.minConfidence ?? 0.30,
                              maxGap: o?.maxGap ?? 1.5)
    } else {
        let dir: ReversalDirection = (o?.direction == "top") ? .top : .bottom
        return .bounceReversal(direction: dir,
                               minAmplitude: o?.minAmplitude ?? 0.12,
                               cooldown: o?.cooldown ?? 0.25,
                               smoothingAlpha: o?.smoothingAlpha ?? 0.5,
                               minConfidence: o?.minConfidence ?? 0.30,
                               maxGap: o?.maxGap ?? 1.5)
    }
}

// --- locate + load the fixture ---

let defaultPath = "../../web-prototype/test/golden.fixtures.json"
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultPath
guard let data = FileManager.default.contents(atPath: path) else {
    FileHandle.standardError.write(Data("SwishStrikeParity: cannot read fixture at \(path)\n".utf8))
    exit(2)
}
let fixture: Fixture
do { fixture = try JSONDecoder().decode(Fixture.self, from: data) }
catch { FileHandle.standardError.write(Data("SwishStrikeParity: bad fixture JSON: \(error)\n".utf8)); exit(2) }

// --- replay each scenario and compare to the JS-frozen golden ---

print("SwishStrikeParity — Swift engine vs JS golden trace (\(fixture.scenarios.count) scenarios)")
var failures = 0
for sc in fixture.scenarios {
    let e = CountingEngine(rule: buildRule(sc.rule))
    for s in sc.samples { _ = e.update(Sample(t: s.t, x: s.x, y: s.y, confidence: s.c)) }
    let times = e.events.map { $0.t }
    var okScenario = e.count == sc.expectedCount && times.count == sc.expectedEventTimes.count
    if okScenario {
        for (a, b) in zip(times, sc.expectedEventTimes) where abs(a - b) > 1e-9 { okScenario = false }
    }
    if okScenario {
        print("  ✔ \(sc.name): count=\(e.count)")
    } else {
        print("  ✘ FAIL \(sc.name): Swift count=\(e.count) times=\(times) | expected count=\(sc.expectedCount) times=\(sc.expectedEventTimes)")
        failures += 1
    }
}

print("")
if failures == 0 {
    print("Parity OK — Swift reproduces the JS golden on all \(fixture.scenarios.count) scenarios.")
} else {
    print("\(failures) scenario(s) DIVERGED.")
    exit(1)
}
