// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Realtime",
  products: [
    .library(
      name: "Realtime",
      targets: ["Realtime"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/daltoniam/Starscream.git", .upToNextMajor(from: "3.0.0"))
  ],
  targets: [
    .target(
      name: "Realtime",
      dependencies: ["Starscream"]
    ),
    .testTarget(
      name: "RealtimeTests",
      dependencies: ["Realtime"]
    ),
  ]
)
