// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Realtime",
  platforms: [
    .iOS(.v13),
    .macCatalyst(.v13),
    .macOS(.v10_15),
    .watchOS(.v6),
    .tvOS(.v13),
  ],
  products: [
    .library(
      name: "Realtime",
      targets: ["Realtime"]
    )
  ],
  targets: [
    .target(
      name: "Realtime",
      dependencies: []
    ),
    .testTarget(
      name: "RealtimeTests",
      dependencies: ["Realtime"]
    ),
  ]
)
