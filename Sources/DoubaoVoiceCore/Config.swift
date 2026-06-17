import CoreGraphics
import Foundation

public enum DoubaoVoiceConfig {
  public static let appName = "DoubaoVoiceToggle"
  public static let launchAgentLabel = "com.yuhanli.doubao-voice-toggle"

  public static let doubaoInputSourceID = "com.bytedance.inputmethod.doubaoime.pinyin"
  public static let f8KeyCode: Int64 = 100
  public static let rightOptionKeyCode = CGKeyCode(61)

  public static var applicationSupportDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
      .appendingPathComponent(appName, isDirectory: true)
  }

  public static var stateURL: URL {
    applicationSupportDirectory.appendingPathComponent("state.json", isDirectory: false)
  }

  public static var binDirectory: URL {
    applicationSupportDirectory.appendingPathComponent("bin", isDirectory: true)
  }

  public static var logDirectory: URL {
    applicationSupportDirectory.appendingPathComponent("logs", isDirectory: true)
  }

  public static var toggleLogURL: URL {
    logDirectory.appendingPathComponent("toggle.log", isDirectory: false)
  }

  public static var toggleErrorLogURL: URL {
    logDirectory.appendingPathComponent("toggle.err.log", isDirectory: false)
  }

  public static var installedToggleURL: URL {
    binDirectory.appendingPathComponent("doubao-voice-toggle", isDirectory: false)
  }
}

public struct VoiceState: Codable {
  public let previousInputSourceID: String
  public let previousOutputMuted: Bool
  public let startedAt: TimeInterval

  public init(previousInputSourceID: String, previousOutputMuted: Bool, startedAt: TimeInterval) {
    self.previousInputSourceID = previousInputSourceID
    self.previousOutputMuted = previousOutputMuted
    self.startedAt = startedAt
  }
}
