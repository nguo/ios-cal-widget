// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CalCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13) // enables `swift test` of the Foundation-only logic off-device
    ],
    products: [
        .library(name: "CalCore", targets: ["CalCore"])
    ],
    targets: [
        .target(name: "CalCore"),
        // XCTest suite — runs in Xcode (XCTest isn't in the CLT toolchain).
        .testTarget(name: "CalCoreTests", dependencies: ["CalCore"]),
        // Foundation-only smoke check — runs anywhere via `swift run calcore-check`,
        // including without Xcode. Mirrors the critical assertions for quick verification.
        .executableTarget(name: "calcore-check", dependencies: ["CalCore"])
    ]
)
