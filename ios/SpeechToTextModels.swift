import Foundation

enum SpeechToTextCleanupStatus: String {
  case disabled
  case pending
  case available
  case modelNotReady = "model-not-ready"
  case unsupportedDevice = "unsupported-device"
  case unsupportedLocale = "unsupported-locale"
  case unavailable
  case failed
}

enum SpeechToTextCleanupStyle: String {
  case dictation
  case note
  case message
}

enum SpeechToTextTranscriptionCapability: String {
  case enhanced
  case basic
  case unavailable
}

enum SpeechToTextModelAssetStatus: String {
  case ready
  case downloadable
  case downloading
  case unavailable
}

struct SpeechToTextCapabilities {
  let transcription: SpeechToTextTranscriptionCapability
  let cleanup: SpeechToTextCleanupStatus
  let modelAssets: SpeechToTextModelAssetStatus
  let supportedLocale: String?

  func asDictionary() -> [String: Any?] {
    [
      "transcription": transcription.rawValue,
      "cleanup": cleanup.rawValue,
      "modelAssets": modelAssets.rawValue,
      "onDeviceOnly": true,
      "supportedLocale": supportedLocale,
    ]
  }
}

struct SpeechToTextTranscriptSegment {
  let text: String
  let startMs: Double?
  let endMs: Double?
  let confidence: Double?

  func asDictionary() -> [String: Any?] {
    [
      "text": text,
      "startMs": startMs,
      "endMs": endMs,
      "confidence": confidence,
    ]
  }
}
