import Carbon
import CoreGraphics
import DoubaoVoiceCore
import Foundation

enum ToggleError: Error, CustomStringConvertible {
  case invalidArguments(String)
  case missingInputSource(String)
  case missingCurrentInputSource
  case sourceSelectionFailed(String)
  case keyPostFailed
  case osascriptFailed(String)

  var description: String {
    switch self {
    case .invalidArguments(let message):
      return message
    case .missingInputSource(let id):
      return "Input source not found: \(id)"
    case .missingCurrentInputSource:
      return "Could not read current input source."
    case .sourceSelectionFailed(let id):
      return "Could not select input source: \(id)"
    case .keyPostFailed:
      return "Could not post synthetic right Option event. Grant Accessibility permission."
    case .osascriptFailed(let message):
      return "osascript failed: \(message)"
    }
  }
}

enum Command {
  case toggle
  case status
  case reset(overrideMuted: Bool?)
  case help
}

func inputSourceID(_ source: TISInputSource) -> String? {
  guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
    return nil
  }
  return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

func currentInputSourceID() -> String? {
  guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
    return nil
  }
  return inputSourceID(source)
}

func inputSource(withID targetID: String) -> TISInputSource? {
  guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
    return nil
  }
  return list.first { inputSourceID($0) == targetID }
}

func selectInputSource(_ id: String) throws {
  guard let source = inputSource(withID: id) else {
    throw ToggleError.missingInputSource(id)
  }

  let status = TISSelectInputSource(source)
  if status != noErr {
    throw ToggleError.sourceSelectionFailed(id)
  }
}

@discardableResult
func runOsa(_ script: String) throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
  process.arguments = ["-e", script]

  let output = Pipe()
  let error = Pipe()
  process.standardOutput = output
  process.standardError = error

  try process.run()
  process.waitUntilExit()

  let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

  guard process.terminationStatus == 0 else {
    throw ToggleError.osascriptFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
  }
  return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
}

func readOutputMuted() throws -> Bool {
  let value = try runOsa("output muted of (get volume settings)")
  return value.lowercased().contains("true")
}

func setOutputMuted(_ muted: Bool) throws {
  _ = try runOsa("set volume output muted \(muted ? "true" : "false")")
}

func postRightOptionTap() throws {
  guard let source = CGEventSource(stateID: .hidSystemState),
        let down = CGEvent(keyboardEventSource: source, virtualKey: DoubaoVoiceConfig.rightOptionKeyCode, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: DoubaoVoiceConfig.rightOptionKeyCode, keyDown: false) else {
    throw ToggleError.keyPostFailed
  }

  down.type = .flagsChanged
  down.flags = .maskAlternate
  up.type = .flagsChanged
  up.flags = []

  down.post(tap: .cghidEventTap)
  usleep(80_000)
  up.post(tap: .cghidEventTap)
}

func ensureApplicationSupportDirectory() throws {
  try FileManager.default.createDirectory(
    at: DoubaoVoiceConfig.applicationSupportDirectory,
    withIntermediateDirectories: true
  )
}

func readState() -> VoiceState? {
  guard let data = try? Data(contentsOf: DoubaoVoiceConfig.stateURL) else {
    return nil
  }
  return try? JSONDecoder().decode(VoiceState.self, from: data)
}

func writeState(_ state: VoiceState) throws {
  try ensureApplicationSupportDirectory()
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(state)
  try data.write(to: DoubaoVoiceConfig.stateURL, options: .atomic)
}

func clearState() {
  try? FileManager.default.removeItem(at: DoubaoVoiceConfig.stateURL)
}

func startVoiceInput() throws {
  guard let previousInputSourceID = currentInputSourceID(), !previousInputSourceID.isEmpty else {
    throw ToggleError.missingCurrentInputSource
  }

  let wasMuted = try readOutputMuted()
  let state = VoiceState(
    previousInputSourceID: previousInputSourceID,
    previousOutputMuted: wasMuted,
    startedAt: Date().timeIntervalSince1970
  )

  try writeState(state)

  do {
    try setOutputMuted(true)
    try selectInputSource(DoubaoVoiceConfig.doubaoInputSourceID)
    usleep(180_000)
    try postRightOptionTap()
    print("Doubao voice input started")
  } catch {
    try? selectInputSource(previousInputSourceID)
    try? setOutputMuted(wasMuted)
    clearState()
    throw error
  }
}

func stopVoiceInput(_ state: VoiceState) throws {
  try postRightOptionTap()
  usleep(650_000)

  var restoreMessages: [String] = []
  do {
    try selectInputSource(state.previousInputSourceID)
  } catch {
    restoreMessages.append("input source restore failed: \(error)")
  }

  do {
    try setOutputMuted(state.previousOutputMuted)
  } catch {
    restoreMessages.append("mute restore failed: \(error)")
  }

  clearState()
  print("Doubao voice input stopped")

  for message in restoreMessages {
    fputs("Warning: \(message)\n", stderr)
  }
}

func resetState(overrideMuted: Bool?) throws {
  let state = readState()

  if let inputSourceID = state?.previousInputSourceID, !inputSourceID.isEmpty {
    try? selectInputSource(inputSourceID)
  }

  if let overrideMuted {
    try setOutputMuted(overrideMuted)
  } else if let state {
    try setOutputMuted(state.previousOutputMuted)
  }

  clearState()
  print("Doubao voice state reset")
}

func printStatus() {
  let state = readState()
  let formatter = ISO8601DateFormatter()

  print("State: \(state == nil ? "inactive" : "active")")
  print("State path: \(DoubaoVoiceConfig.stateURL.path)")
  print("Current input source: \(currentInputSourceID() ?? "unknown")")
  if let muted = try? readOutputMuted() {
    print("Output muted: \(muted)")
  } else {
    print("Output muted: unknown")
  }

  if let state {
    print("Previous input source: \(state.previousInputSourceID)")
    print("Previous output muted: \(state.previousOutputMuted)")
    print("Started at: \(formatter.string(from: Date(timeIntervalSince1970: state.startedAt)))")
  }
}

func printHelp() {
  print("""
  Usage: doubao-voice-toggle [--status | --reset [--muted true|false] | --help]

  With no arguments, toggles Doubao voice input:
    first run   saves input/mute state, mutes output, selects Doubao, taps right Option
    second run  taps right Option, restores saved input source and mute state
  """)
}

func parseCommand(_ arguments: [String]) throws -> Command {
  var args = Array(arguments.dropFirst())

  if args.isEmpty {
    return .toggle
  }

  let first = args.removeFirst()
  switch first {
  case "--status", "status":
    guard args.isEmpty else {
      throw ToggleError.invalidArguments("--status does not accept additional arguments")
    }
    return .status
  case "--help", "-h", "help":
    return .help
  case "--reset", "reset":
    var overrideMuted: Bool?
    while !args.isEmpty {
      let option = args.removeFirst()
      switch option {
      case "--muted":
        guard let value = args.first else {
          throw ToggleError.invalidArguments("--muted requires true or false")
        }
        args.removeFirst()
        switch value.lowercased() {
        case "true", "yes", "1":
          overrideMuted = true
        case "false", "no", "0":
          overrideMuted = false
        default:
          throw ToggleError.invalidArguments("--muted requires true or false")
        }
      default:
        throw ToggleError.invalidArguments("Unknown reset option: \(option)")
      }
    }
    return .reset(overrideMuted: overrideMuted)
  default:
    throw ToggleError.invalidArguments("Unknown command: \(first)")
  }
}

do {
  switch try parseCommand(CommandLine.arguments) {
  case .toggle:
    if let state = readState() {
      try stopVoiceInput(state)
    } else {
      try startVoiceInput()
    }
  case .status:
    printStatus()
  case .reset(let overrideMuted):
    try resetState(overrideMuted: overrideMuted)
  case .help:
    printHelp()
  }
} catch {
  fputs("Doubao voice toggle failed: \(error)\n", stderr)
  exit(1)
}
