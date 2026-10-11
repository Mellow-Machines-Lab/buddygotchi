// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The package sits at the repo root because SwiftPM won't take a target
// outside its root, and the app's targets live in both app/ (what ships)
// and internal/ (what doesn't). Production targets (BoopKit, Boop) never
// depend on internal ones (internal/README.md).

// There's no Xcode here, so the tests are an executable that `@testable
// import`s the libraries, which must be built with testability enabled.
let testable: [SwiftSetting] = [.unsafeFlags(["-enable-testing"])]

/// agent-hooks' library, which every Boop target that sees agents imports.
let agentHooks: Target.Dependency = .product(name: "AgentHooks", package: "agent-hooks")
/// MellowHarness's library, which every Boop target that touches the brain, its
/// log or its events imports.
let mellowharness: Target.Dependency = .product(name: "MellowHarness", package: "mellowharness")
/// LinkKit's library, which every Boop target that talks to the device
/// imports.
let linkKit: Target.Dependency = .product(name: "LinkKit", package: "linkkit")

/// Everything in the repo except `kept` and the directories leading to them,
/// for a target whose path is the repo root: SwiftPM warns about each file
/// under a target's path that no rule handles. Hidden entries (.git,
/// .build) are left out, as SwiftPM skips them itself.
func excludingAllBut(_ kept: [String]) -> [String] {
    var parents: Set<String> = [""]
    for path in kept {
        var parent = ""
        for part in path.split(separator: "/").dropLast() {
            parent = parent.isEmpty ? String(part) : parent + "/" + part
            parents.insert(parent)
        }
    }
    return parents.sorted().flatMap { parent -> [String] in
        let dir = parent.isEmpty ? Context.packageDirectory : Context.packageDirectory + "/" + parent
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return entries.filter { !$0.hasPrefix(".") }.sorted().compactMap { entry in
            let path = parent.isEmpty ? entry : parent + "/" + entry
            return kept.contains(path) || parents.contains(path) ? nil : path
        }
    }
}

var packageTargets: [Target] = [
    // Everything that isn't the app shell: Adapters, Core, Harness, Brains,
    // Actions, Voice, Memory, DeviceLink (Boop's vocabulary on LinkKit),
    // the hook installer (Install) and the Runtime that wires them together
    // (App) (documentation/architecture.html).
    .target(
        name: "BoopKit",
        dependencies: [mellowharness, agentHooks, linkKit],
        path: "app/BoopKit",
        swiftSettings: testable
    ),
    // The menu-bar app. `Boop --headless` runs it without UI or Bluetooth
    // and `Boop --snapshots` draws its panes; both ship in the binary, but
    // their sources are in internal/app/Boop.
    // Push-to-talk's mic lives in the app, in app/Boop/Talk.swift.
    // Info.plist is linked into the binary with -sectcreate, so macOS finds
    // LSUIElement (a menu-bar app, no Dock icon) and the Bluetooth,
    // microphone and speech usage descriptions without an app bundle.
    // The character pack is bundled as `make build` stages it
    // (characters/charactergen.py --stage, characters/CHARACTER.md §2):
    // the chosen pack, from .character-build/packs.
    .executableTarget(
        name: "Boop",
        dependencies: ["BoopKit", agentHooks, mellowharness, linkKit],
        path: ".",
        exclude: excludingAllBut(["app/Boop", "internal/app/Boop"])
            + ["app/Boop/Info.plist"],
        sources: ["app/Boop/main.swift", "app/Boop/MenuBarApp.swift", "app/Boop/PresenceSignals.swift",
                  "app/Boop/Talk.swift", "app/Boop/Views", "internal/app/Boop"],
        resources: [.copy(".character-build/packs")],
        linkerSettings: [.linkedFramework("WebKit"), .unsafeFlags([
            "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
            "-Xlinker", Context.packageDirectory + "/app/Boop/Info.plist",
        ])]
    ),
    // Internal from here on: none of it ships.

    // What boopdev and the tests share: the harness evals (Eval) and hook
    // replay.
    .target(
        name: "BoopDevKit",
        dependencies: ["BoopKit", agentHooks, mellowharness, linkKit],
        path: "internal/app/BoopDevKit",
        swiftSettings: testable
    ),
    // Developer CLI: the evals, reading debug logs, replay, voice lines
    // and the hook installer (hooks).
    .executableTarget(
        name: "BoopDev",
        dependencies: ["BoopKit", "BoopDevKit", agentHooks, mellowharness],
        path: "internal/app/BoopDev"
    ),
]

// SwiftPM's `swift test` would build tests against the XCTest shim and run
// NONE of them (a false green). Instead the Tests directory builds as an
// executable driven by the generated GeneratedTestRunner.swift, run by
// `make -C internal test`. See internal/app/tools/gen-test-runner.py.
packageTargets += [
    .executableTarget(
        name: "BoopTests",
        dependencies: ["BoopKit", "BoopDevKit", "XCTest", agentHooks, mellowharness, linkKit],
        path: "internal/app/Tests",
        exclude: ["Fixtures"],
        swiftSettings: [.define("BOOP_SHIM_RUNNER")]
    ),
    .target(
        name: "XCTest",
        path: "internal/app/TestSupport/XCTestShim"
    ),
]

let package = Package(
    name: "Boop",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Boop", targets: ["Boop"]),
        .executable(name: "boopdev", targets: ["BoopDev"]),
    ],
    // The hook layer (agent-hooks/README.md), the brain's harness
    // (mellowharness/README.md) and the device link (linkkit/README.md) are
    // packages of their own: Boop depends on them, and they on nothing here.
    // Their tools, agent-hook, mellowharness-emit and beacon, are built from them
    // by name (`swift build --product agent-hook`).
    dependencies: [.package(path: "agent-hooks"), .package(path: "mellowharness"), .package(path: "linkkit")],
    targets: packageTargets
)
