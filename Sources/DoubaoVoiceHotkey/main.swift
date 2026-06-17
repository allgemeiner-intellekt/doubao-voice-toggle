import CoreGraphics
import DoubaoVoiceCore
import Foundation

var lastTriggerAt = Date.distantPast

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

func runToggleHelper() {
  let helperURL = toggleURL()
  let process = Process()
  process.executableURL = helperURL
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice

  do {
    try process.run()
  } catch {
    NSLog("Doubao voice hotkey failed to run \(helperURL.path): \(error)")
  }
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
