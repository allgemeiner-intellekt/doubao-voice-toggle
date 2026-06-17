import CoreGraphics
import DoubaoVoiceCore
import Foundation

var lastTriggerAt = Date.distantPast
let toggleRunLock = NSLock()
var toggleRunInFlight = false

func printHelp() {
  print("""
  Usage: doubao-voice-hotkey [--request-permissions | --help]

  With no arguments, listens for F8 and runs doubao-voice-toggle.
  """)
}

@discardableResult
func requestListenEventPermission() -> Bool {
  if CGPreflightListenEventAccess() {
    return true
  }
  return CGRequestListenEventAccess()
}

func fileExistsAndIsExecutable(_ url: URL) -> Bool {
  FileManager.default.isExecutableFile(atPath: url.path)
}

func siblingToggleURL() -> URL? {
  guard let executableURL = Bundle.main.executableURL else {
    return nil
  }
  let candidate = executableURL
    .deletingLastPathComponent()
    .appendingPathComponent("doubao-voice-toggle", isDirectory: false)
  return fileExistsAndIsExecutable(candidate) ? candidate : nil
}

func toggleURL() -> URL {
  if let override = ProcessInfo.processInfo.environment["DOUBAO_VOICE_TOGGLE_HELPER"], !override.isEmpty {
    return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
  }

  if let sibling = siblingToggleURL() {
    return sibling
  }

  return DoubaoVoiceConfig.installedToggleURL
}

func ensureLogDirectory() {
  try? FileManager.default.createDirectory(
    at: DoubaoVoiceConfig.logDirectory,
    withIntermediateDirectories: true
  )
}

func appendFileHandle(at url: URL) throws -> FileHandle {
  ensureLogDirectory()

  if !FileManager.default.fileExists(atPath: url.path) {
    FileManager.default.createFile(atPath: url.path, contents: nil)
  }

  let handle = try FileHandle(forWritingTo: url)
  try handle.seekToEnd()
  return handle
}

func logHotkey(_ message: String) {
  let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
  print(line, terminator: "")
  fflush(stdout)
}

func beginToggleRun() -> Bool {
  toggleRunLock.lock()
  defer { toggleRunLock.unlock() }

  if toggleRunInFlight {
    return false
  }

  toggleRunInFlight = true
  return true
}

func endToggleRun() {
  toggleRunLock.lock()
  toggleRunInFlight = false
  toggleRunLock.unlock()
}

func appendData(_ data: Data, to url: URL) {
  guard !data.isEmpty else {
    return
  }

  do {
    let handle = try appendFileHandle(at: url)
    defer { try? handle.close() }
    try handle.write(contentsOf: data)
  } catch {
    NSLog("Doubao voice hotkey failed to append \(url.path): \(error)")
  }
}

func runToggleHelper() {
  let helperURL = toggleURL()
  guard beginToggleRun() else {
    logHotkey("F8 ignored; toggle already running")
    return
  }

  logHotkey("F8 accepted; running \(helperURL.path)")

  DispatchQueue.global(qos: .userInitiated).async {
    defer { endToggleRun() }

    let process = Process()
    process.executableURL = helperURL

    do {
      let stdout = Pipe()
      let stderr = Pipe()

      process.standardOutput = stdout
      process.standardError = stderr
      try process.run()
      process.waitUntilExit()

      appendData(stdout.fileHandleForReading.readDataToEndOfFile(), to: DoubaoVoiceConfig.toggleLogURL)
      appendData(stderr.fileHandleForReading.readDataToEndOfFile(), to: DoubaoVoiceConfig.toggleErrorLogURL)

      if process.terminationStatus != 0 {
        logHotkey("toggle exited with status \(process.terminationStatus); see \(DoubaoVoiceConfig.toggleErrorLogURL.path)")
      }
    } catch {
      NSLog("Doubao voice hotkey failed to run \(helperURL.path): \(error)")
    }
  }
}

switch CommandLine.arguments.dropFirst().first {
case nil:
  break
case "--request-permissions"?, "request-permissions"?:
  let allowed = requestListenEventPermission()
  print("Input Monitoring permission: \(allowed ? "granted" : "not granted")")
  exit(allowed ? 0 : 1)
case "--help"?, "-h"?, "help"?:
  printHelp()
  exit(0)
case let argument?:
  fputs("Unknown argument: \(argument)\n", stderr)
  exit(1)
}

guard requestListenEventPermission() else {
  fputs("""
  Failed to get Input Monitoring permission.
  Grant Input Monitoring permission to doubao-voice-hotkey, then restart it.
  Installed path: \(DoubaoVoiceConfig.binDirectory.path)/doubao-voice-hotkey

  """, stderr)
  exit(1)
}

let callback: CGEventTapCallBack = { _, type, event, _ in
  guard type == .keyDown else {
    return Unmanaged.passUnretained(event)
  }

  let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
  let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat)

  guard keyCode == DoubaoVoiceConfig.f8KeyCode else {
    return Unmanaged.passUnretained(event)
  }

  if autorepeat == 0 {
    let now = Date()
    if now.timeIntervalSince(lastTriggerAt) > 0.35 {
      lastTriggerAt = now
      runToggleHelper()
    }
  }

  return nil
}

let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
guard let tap = CGEvent.tapCreate(
  tap: .cgSessionEventTap,
  place: .headInsertEventTap,
  options: .defaultTap,
  eventsOfInterest: mask,
  callback: callback,
  userInfo: nil
) else {
  fputs("""
  Failed to create F8 event tap.
  Grant Input Monitoring and Accessibility permission to doubao-voice-hotkey, then restart it.
  Installed path: \(DoubaoVoiceConfig.binDirectory.path)/doubao-voice-hotkey

  """, stderr)
  exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("Doubao voice hotkey listener running. Press F8 to toggle.")
fflush(stdout)
CFRunLoopRun()
