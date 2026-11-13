// swift-tools-version: 5.10
import PackageDescription

// mac++: one menu-bar app holding MacsPane and MacsBored, each a page of one dropdown.
//   • MacsShared                   , what both apps use: the tabbed dropdown and its bubble.
//   • MacsPaneCore / MacsPaneKit   , the window manager: drag a window to the notch to snap it.
//   • MacsBoredCore / MacsBoredKit , macOS's shortcuts handed to remote-desktop apps, plus triggers.
//   • MacPlusPlusKit               , the app: one menu-bar icon, both apps, first-run setup.
//   • mac-plus-plus                , the executable that boots it: `swift run mac-plus-plus`.
// Each Core is pure logic with its tests (no AppKit); each Kit is the AppKit/SwiftUI app. The signed
// .app is built by Xcode from project.yml and reuses MacPlusPlusKit.
let package = Package(
    name: "MacPlusPlus",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacPlusPlusKit", targets: ["MacPlusPlusKit"]),
        .executable(name: "mac-plus-plus", targets: ["MacPlusPlus"]),
    ],
    targets: [
        .target(name: "MacsShared"),
        .target(name: "MacsPaneCore"),
        .target(name: "MacsPaneKit", dependencies: ["MacsPaneCore", "MacsShared"]),
        .testTarget(name: "MacsPaneCoreTests", dependencies: ["MacsPaneCore"]),
        .target(name: "MacsBoredCore"),
        .target(name: "MacsBoredKit", dependencies: ["MacsBoredCore", "MacsShared"]),
        .testTarget(name: "MacsBoredCoreTests", dependencies: ["MacsBoredCore"]),
        .target(name: "MacPlusPlusKit", dependencies: ["MacsShared", "MacsPaneKit", "MacsBoredKit"]),
        .executableTarget(name: "MacPlusPlus", dependencies: ["MacPlusPlusKit"]),
    ]
)
