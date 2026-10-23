// swift-tools-version: 6.0
import PackageDescription

// Baika — the engine. Styles, voices, the story prompt, the text sanitizer, the narration
// chunker and the fallback rules. No UI in here; the app in App/ renders what this package
// returns. BaikaAccounts is the thin bridge to the Fabrique accounts hub (sign-in, the script
// stream, the narration request). The Xcode project (project.yml → XcodeGen) consumes this
// package, so the package tests and Xcode compile exactly the same files.
// Swift 6 language mode: strict concurrency is on, and every model is Sendable.
let package = Package(
    name: "BaikaKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "BaikaKit", targets: ["BaikaKit"]),
        .library(name: "BaikaAccounts", targets: ["BaikaAccounts"]),
    ],
    dependencies: [
        // Pinned to a tag, like Finca, Knut and Lumi: a floating branch would let a fresh
        // clone and a TestFlight archive build different kits.
        .package(url: "https://github.com/Fabrique-Futur/accounts.git", from: "0.1.7"),
    ],
    targets: [
        .target(name: "BaikaKit"),
        // The one place the app meets the Fabrique accounts hub. BaikaKit stays free of the
        // network: it defines `ScriptBackend` and `NarrationBackend`, this target carries them.
        .target(
            name: "BaikaAccounts",
            dependencies: [
                "BaikaKit",
                .product(name: "FabriqueAccounts", package: "accounts"),
            ]
        ),
        .testTarget(name: "BaikaKitTests", dependencies: ["BaikaKit"]),
        .testTarget(name: "BaikaAccountsTests", dependencies: ["BaikaAccounts", "BaikaKit"]),
    ]
)
