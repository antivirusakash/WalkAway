// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "WalkAway",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "WalkAway", targets: ["WalkAway"])
  ],
  targets: [
    .executableTarget(
      name: "WalkAway",
      path: "Sources/WalkAway"
    )
  ]
)
