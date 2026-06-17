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

func logToggle(_ message: String) {
  let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
  try? FileManager.default.createDirectory(
    at: DoubaoVoiceConfig.logDirectory,
    withIntermediateDirectories: true
  )
  FileManager.default.createFile(atPath: DoubaoVoiceConfig.toggleLogURL.path, contents: nil)

  if let handle = try? FileHandle(forWritingTo: DoubaoVoiceConfig.toggleLogURL) {
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    if let data = line.data(using: .utf8) {
      _ = try? handle.write(contentsOf: data)
    }
  }
}

enum Command {
  case toggle
  case status
  case reset(overrideMuted: Bool?)
  case requestPermissions
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

func selectInputSourceWithRetry(_ id: String, timeout: TimeInterval = 2.0) throws {
  let deadline = Date().addingTimeInterval(timeout)
  var lastError: Error?

  repeat {
    do {
      try selectInputSource(id)
      usleep(100_000)

      if currentInputSourceID() == id {
        return
      }

      lastError = ToggleError.sourceSelectionFailed(id)
    } catch {
      lastError = error
    }

    usleep(150_000)
  } while Date() < deadline

  throw lastError ?? ToggleError.sourceSelectionFailed(id)
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

@discardableResult
func requestPostEventPermission() -> Bool {
  if CGPreflightPostEventAccess() {
    return true
  }
  return CGRequestPostEventAccess()
}

func postRightOptionTap() throws {
  guard requestPostEventPermission() else {
    throw ToggleError.keyPostFailed
  }

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
  try FileManager.default.createDirectory(
    at: DoubaoVoiceConfig.logDirectory,
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
  logToggle("start: previousInputSourceID=\(previousInputSourceID), previousOutputMuted=\(wasMuted)")
  let state = VoiceState(
    previousInputSourceID: previousInputSourceID,
    previousOutputMuted: wasMuted,
    startedAt: Date().timeIntervalSince1970
  )

  try writeState(state)

  do {
    try setOutputMuted(true)
    try selectInputSourceWithRetry(DoubaoVoiceConfig.doubaoInputSourceID, timeout: 1.0)
    logToggle("start: selected Doubao, currentInputSourceID=\(currentInputSourceID() ?? "unknown")")
    usleep(180_000)
    try postRightOptionTap()
    logToggle("start: posted right Option")
    print("Doubao voice input started")
  } catch {
    try? selectInputSourceWithRetry(previousInputSourceID, timeout: 1.0)
    try? setOutputMuted(wasMuted)
    clearState()
    throw error
  }
}

func stopVoiceInput(_ state: VoiceState) throws {
  logToggle("stop: restoring previousInputSourceID=\(state.previousInputSourceID), currentBeforeStop=\(currentInputSourceID() ?? "unknown")")
  try postRightOptionTap()
  logToggle("stop: posted right Option")

  var restoreMessages: [String] = []
  usleep(900_000)

  let deadline = Date().addingTimeInterval(3.0)
  var attempt = 0
  var stableChecks = 0

  while Date() < deadline {
    let currentID = currentInputSourceID()

    if currentID == state.previousInputSourceID {
      stableChecks += 1
      logToggle("stop: restore stable check \(stableChecks), current=\(currentID ?? "unknown")")

      if stableChecks >= 3 {
        break
      }

      usleep(250_000)
      continue
    }

    stableChecks = 0
    attempt += 1

    do {
      try selectInputSourceWithRetry(state.previousInputSourceID, timeout: 0.6)
      logToggle("stop: restore attempt \(attempt) selected \(state.previousInputSourceID), current=\(currentInputSourceID() ?? "unknown")")
    } catch {
      let message = "input source restore attempt \(attempt) failed: \(error)"
      logToggle("stop: \(message)")
      restoreMessages.append(message)
    }

    usleep(250_000)
  }

  do {
    try setOutputMuted(state.previousOutputMuted)
    logToggle("stop: restored output muted=\(state.previousOutputMuted)")
  } catch {
    restoreMessages.append("mute restore failed: \(error)")
  }

  clearState()
  logToggle("stop: cleared state, finalCurrentInputSourceID=\(currentInputSourceID() ?? "unknown")")
  print("Doubao voice input stopped")

  for message in restoreMessages {
    fputs("Warning: \(message)\n", stderr)
  }
}

func resetState(overrideMuted: Bool?) throws {
  let state = readState()

  if let inputSourceID = state?.previousInputSourceID, !inputSourceID.isEmpty {
    try? selectInputSourceWithRetry(inputSourceID)
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
  print("Can post synthetic key events: \(CGPreflightPostEventAccess())")
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
  Usage: doubao-voice-toggle [--status | --reset [--muted true|false] | --request-permissions | --help]

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
  case "--request-permissions", "request-permissions":
    guard args.isEmpty else {
      throw ToggleError.invalidArguments("--request-permissions does not accept additional arguments")
    }
    return .requestPermissions
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
  case .requestPermissions:
    let allowed = requestPostEventPermission()
    print("Synthetic key event permission: \(allowed ? "granted" : "not granted")")
  case .help:
    printHelp()
  }
} catch {
  fputs("Doubao voice toggle failed: \(error)\n", stderr)
  exit(1)
}
