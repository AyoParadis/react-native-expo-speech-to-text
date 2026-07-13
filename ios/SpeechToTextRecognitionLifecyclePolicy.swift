import Foundation

enum SpeechToTextMode: String {
  case single
  case continuous
}

enum SpeechToTextSilenceAction: Equatable {
  case commitPendingAndFinalize
  case commitPendingAndRestart
  case none
}

enum SpeechToTextNonFinalResultAction: Equatable {
  case scheduleSilenceTimeout
  case preserveStopWatchdog
}

struct SpeechToTextRecognitionLifecyclePolicy {
  static func actionAfterSilence(
    mode: SpeechToTextMode,
    stopRequested: Bool
  ) -> SpeechToTextSilenceAction {
    guard !stopRequested else {
      return .none
    }

    switch mode {
    case .single:
      return .commitPendingAndFinalize
    case .continuous:
      return .commitPendingAndRestart
    }
  }

  static func actionAfterNonFinalResult(
    stopRequested: Bool
  ) -> SpeechToTextNonFinalResultAction {
    stopRequested ? .preserveStopWatchdog : .scheduleSilenceTimeout
  }
}
