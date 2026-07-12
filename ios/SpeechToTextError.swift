import ExpoModulesCore
import Foundation

enum SpeechToTextErrorCode: String {
  case speechRecognizerNotAvailable = "ERR_SPEECH_RECOGNIZER_NOT_AVAILABLE"
  case recordingStartFailed = "ERR_RECORDING_START_FAILED"
  case recognitionFailed = "ERR_RECOGNITION_FAILED"
  case permissionDenied = "ERR_PERMISSION_DENIED"
  case permissionRestricted = "ERR_PERMISSION_RESTRICTED"
  case permissionNotDetermined = "ERR_PERMISSION_NOT_DETERMINED"
  case invalidState = "ERR_INVALID_STATE"
  case unknown = "ERR_UNKNOWN"
}

enum SpeechToTextPermissionStatus: String {
  case granted = "granted"
  case denied = "denied"
  case restricted = "restricted"
  case undetermined = "undetermined"
}

struct SpeechToTextError: Error {
  let code: SpeechToTextErrorCode
  let message: String

  static let speechRecognizerNotAvailable = SpeechToTextError(
    code: .speechRecognizerNotAvailable,
    message: "Speech recognition is not available on this device"
  )
  static let recordingStartFailed = SpeechToTextError(
    code: .recordingStartFailed,
    message: "Failed to start audio recording"
  )
  static let recognitionFailed = SpeechToTextError(
    code: .recognitionFailed,
    message: "Failed to recognize speech"
  )
  static let permissionDenied = SpeechToTextError(
    code: .permissionDenied,
    message: "Speech recognition permission was denied"
  )
  static let permissionRestricted = SpeechToTextError(
    code: .permissionRestricted,
    message: "Speech recognition is restricted on this device"
  )
  static let permissionNotDetermined = SpeechToTextError(
    code: .permissionNotDetermined,
    message: "Speech recognition permission was not yet determined"
  )
  static let invalidState = SpeechToTextError(
    code: .invalidState,
    message: "Invalid state, cannot perform action"
  )

  static func unknown(message: String) -> SpeechToTextError {
    SpeechToTextError(code: .unknown, message: message)
  }

  static func recordingStartFailed(message: String) -> SpeechToTextError {
    SpeechToTextError(
      code: .recordingStartFailed,
      message: message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? Self.recordingStartFailed.message
        : message
    )
  }
}

final class SpeechToTextException: Exception, @unchecked Sendable {
  private let exceptionCode: String
  private let exceptionReason: String

  init(_ error: SpeechToTextError) {
    self.exceptionCode = error.code.rawValue
    self.exceptionReason = error.message
    super.init()
  }

  override var code: String {
    exceptionCode
  }

  override var reason: String {
    exceptionReason
  }
}
