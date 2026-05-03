// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BarelyReal",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BarelyRealCore", targets: ["BarelyRealCore"]),
        .executable(name: "BarelyReal", targets: ["BarelyReal"]),
        .executable(name: "BarelyRealKmSmoke", targets: ["BarelyRealKmSmoke"]),
        .executable(name: "BarelyRealTests", targets: ["BarelyRealTests"]),
    ],
    targets: [
        .target(
            name: "BarelyRealCore",
            path: "Core"
        ),
        .executableTarget(
            name: "BarelyReal",
            dependencies: ["BarelyRealCore"],
            path: "App"
        ),
        .executableTarget(
            name: "BarelyRealKmSmoke",
            dependencies: ["BarelyRealCore"],
            path: "Tools/KmSmoke"
        ),
        // Hand-rolled test runner — works with Command Line Tools alone (no XCTest needed).
        // Run with: `swift run BarelyRealTests`
        .executableTarget(
            name: "BarelyRealTests",
            dependencies: ["BarelyRealCore"],
            path: "Tests"
        ),
    ]
)
