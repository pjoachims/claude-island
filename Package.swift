// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Atoll",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(name: "Atoll", dependencies: ["SwiftTerm"], path: "Sources/Atoll"),
        // NB: path must not case-fold onto Sources/Atoll (APFS is
        // case-insensitive; "Sources/atoll" silently overwrote it once)
        .executableTarget(name: "atoll-cli", path: "Sources/cli"),
    ]
)
