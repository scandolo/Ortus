// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ortus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Ortus",
            path: "Ortus",
            exclude: ["Info.plist", "Ortus.entitlements"],
            resources: [.process("Assets.xcassets")]
        ),
    ]
)
