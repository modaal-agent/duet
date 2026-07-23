// swift-tools-version:6.0
import PackageDescription

// The SKIE-route packaging receipt's Swift half: consume the Kotlin/Native
// DuetReceipt.xcframework (kernel + the lamp receipt feature) and replay the
// committed kotlin-corpus fixtures across the boundary. Build the framework
// BEFORE `swift test`:
//   ../../gradlew -p ../.. :consumer-receipt:assembleDuetReceiptDebugXCFramework
let package = Package(
  name: "DuetReceiptConsumer",
  platforms: [.macOS(.v13)],
  targets: [
    .binaryTarget(
      name: "DuetReceipt",
      path: "../build/XCFrameworks/debug/DuetReceipt.xcframework"
    ),
    .testTarget(
      name: "ReceiptTests",
      dependencies: ["DuetReceipt"],
      linkerSettings: [
        // DuetReceipt is a static Kotlin/Native framework; its C++ runtime
        // pulls in libc++ symbols Swift does not autolink.
        .linkedLibrary("c++"),
        .linkedFramework("Foundation"),
      ]
    ),
  ]
)
