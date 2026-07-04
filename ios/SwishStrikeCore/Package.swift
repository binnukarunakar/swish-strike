// swift-tools-version: 5.9
import PackageDescription

// SwishStrikeCore — the pure, platform-agnostic core of the Swish Strike app.
// No UIKit, no AVFoundation, no Vision. Just the data model + counting engine,
// so it compiles and tests on any Mac with no Xcode needed.
//
// Two ways to verify it:
//   • `swift run SwishStrikeCoreCheck`  — headless assertion harness, works WITHOUT
//                                   Xcode (no XCTest). This is the one that runs
//                                   in this repo's CI-on-a-bare-toolchain setup.
//   • `swift test`                — the idiomatic XCTest suite (needs Xcode /
//                                   the XCTest framework installed).
// Both exercise the same scenarios; keep them in sync with the JS suite.
let package = Package(
    name: "SwishStrikeCore",
    products: [
        .library(name: "SwishStrikeCore", targets: ["SwishStrikeCore"]),
        .executable(name: "SwishStrikeCoreCheck", targets: ["SwishStrikeCoreCheck"]),
        .executable(name: "SwishStrikeParity", targets: ["SwishStrikeParity"]),
    ],
    targets: [
        .target(name: "SwishStrikeCore"),
        .executableTarget(name: "SwishStrikeCoreCheck", dependencies: ["SwishStrikeCore"]),
        // Replays the shared golden trace (web-prototype/test/golden.fixtures.json)
        // through the Swift engine — the cross-language parity proof.
        .executableTarget(name: "SwishStrikeParity", dependencies: ["SwishStrikeCore"]),
        .testTarget(name: "SwishStrikeCoreTests", dependencies: ["SwishStrikeCore"]),
    ]
)
