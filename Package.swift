// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "doubao-voice-toggle",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "doubao-voice-toggle", targets: ["DoubaoVoiceToggle"]),
    .executable(name: "doubao-voice-hotkey", targets: ["DoubaoVoiceHotkey"])
  ],
  targets: [
    .target(name: "DoubaoVoiceCore"),
    .executableTarget(
      name: "DoubaoVoiceToggle",
      dependencies: ["DoubaoVoiceCore"]
    ),
    .executableTarget(
      name: "DoubaoVoiceHotkey",
      dependencies: ["DoubaoVoiceCore"]
    )
  ]
)
