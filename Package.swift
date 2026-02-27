// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ortus",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Ortus",
            path: "Ortus",
            exclude: ["Info.plist", "Ortus.entitlements"],
            resources: [.process("Assets.xcassets")]
        ),
    ]
)
