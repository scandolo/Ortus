// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ortus",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.59.3"),
    ],
    targets: [
        .target(name: "OrtusCore"),
        .executableTarget(name: "OrtusBrowserBridge", dependencies: ["OrtusCore"]),
        .executableTarget(name: "OrtusCoreChecks", dependencies: ["OrtusCore"], path: "Tests/OrtusCoreTests"),
        .executableTarget(
            name: "Ortus",
            dependencies: [
                "OrtusCore",
                .product(name: "PostHog", package: "posthog-ios"),
            ],
            path: "Ortus",
            exclude: ["Info.plist", "Ortus.entitlements"],
            resources: [.process("Assets.xcassets")]
        ),
    ]
)
