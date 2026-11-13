// swift-tools-version: 5.10
import PackageDescription

// MacsPane and MacsBored, side by side in one package.
//   • MacsPaneCore / MacsPaneKit   , the window manager: drag a window to the notch to snap it.
//   • MacsBoredCore / MacsBoredKit , macOS's shortcuts handed to remote-desktop apps, plus triggers.
// Each Core is pure logic with its tests (no AppKit); each Kit is the AppKit/SwiftUI app.
let package = Package(
    name: "MacPlusPlus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "macspane", targets: ["MacsPane"]),
        .executable(name: "macsbored", targets: ["MacsBored"]),
    ],
    targets: [
        .target(name: "MacsPaneCore"),
        .target(name: "MacsPaneKit", dependencies: ["MacsPaneCore"]),
        .executableTarget(name: "MacsPane", dependencies: ["MacsPaneKit"]),
        .testTarget(name: "MacsPaneCoreTests", dependencies: ["MacsPaneCore"]),
        .target(name: "MacsBoredCore"),
        .target(name: "MacsBoredKit", dependencies: ["MacsBoredCore"]),
        .executableTarget(name: "MacsBored", dependencies: ["MacsBoredKit"]),
        .testTarget(name: "MacsBoredCoreTests", dependencies: ["MacsBoredCore"]),
    ]
)
