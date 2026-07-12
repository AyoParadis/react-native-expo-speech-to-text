import ExpoModulesCore

public final class ExpoSpeechToTextModule: Module, SpeechToTextControllerDelegate {
  private let availabilityEvent = "onAvailabilityChange"
  private let listeningEvent = "onListeningStateChange"
  private let readyEvent = "onReadyStateChange"
  private let stoppingEvent = "onStoppingStateChange"
  private let transcriptEvent = "onTranscript"
  private let errorEvent = "onError"

  private var controller: SpeechToTextController?
  private var hasObservers = false

  private func getController() -> SpeechToTextController {
    if let controller {
      return controller
    }

    let nextController = SpeechToTextController()
    nextController.delegate = self
    controller = nextController
    return nextController
  }

  public func definition() -> ModuleDefinition {
    Name("ExpoSpeechToText")

    Events(
      availabilityEvent,
      listeningEvent,
      readyEvent,
      stoppingEvent,
      transcriptEvent,
      errorEvent
    )

    OnStartObserving {
      self.hasObservers = true
    }

    OnStopObserving {
      self.hasObservers = false
    }

    OnDestroy {
      self.controller?.invalidate()
      self.controller = nil
    }

    AsyncFunction("getStateAsync") {
      self.getController().getState()
    }

    AsyncFunction("getPermissionStatusAsync") {
      self.getController().getPermissionStatus().rawValue
    }

    AsyncFunction("getCapabilitiesAsync") { (promise: Promise) in
      self.getController().getCapabilities { capabilities in
        promise.resolve(capabilities)
      }
    }

    AsyncFunction("prepareOnDeviceModelsAsync") { (options: [String: Any], promise: Promise) in
      self.getController().prepareOnDeviceModels(options: options) { capabilities in
        promise.resolve(capabilities)
      }
    }

    AsyncFunction("getSupportedLocalesAsync") {
      self.getController().getSupportedLocales()
    }

    AsyncFunction("requestPermissionsAsync") { (promise: Promise) in
      self.getController().requestPermissions { status in
        promise.resolve(status.rawValue)
      }
    }

    AsyncFunction("startListening") { (options: [String: Any], promise: Promise) in
      self.getController().startListening(options: options) { result in
        switch result {
        case .success:
          promise.resolve(nil)
        case .failure(let error):
          promise.reject(SpeechToTextException(error))
        }
      }
    }

    AsyncFunction("stopListening") { (promise: Promise) in
      self.getController().stopListening()
      promise.resolve(nil)
    }

    Function("resetTranscript") {
      self.getController().resetTranscript()
    }
  }

  func speechToTextControllerDidChangeAvailability(_ available: Bool) {
    guard hasObservers else { return }
    sendEvent(availabilityEvent, ["available": available])
  }

  func speechToTextControllerDidChangeListening(_ listening: Bool) {
    guard hasObservers else { return }
    sendEvent(listeningEvent, ["listening": listening])
  }

  func speechToTextControllerDidChangeReady(_ ready: Bool) {
    guard hasObservers else { return }
    sendEvent(readyEvent, ["ready": ready])
  }

  func speechToTextControllerDidChangeStopping(_ stopping: Bool) {
    guard hasObservers else { return }
    sendEvent(stoppingEvent, ["stopping": stopping])
  }

  func speechToTextControllerDidUpdateTranscript(
    _ transcript: String?,
    rawTranscript: String?,
    cleanedTranscript: String?,
    cleanupStatus: SpeechToTextCleanupStatus,
    engine: String?,
    segments: [SpeechToTextTranscriptSegment],
    isFinal: Bool
  ) {
    guard hasObservers else { return }
    sendEvent(transcriptEvent, [
      "transcript": transcript,
      "rawTranscript": rawTranscript,
      "cleanedTranscript": cleanedTranscript,
      "cleanupStatus": cleanupStatus.rawValue,
      "engine": engine,
      "segments": segments.map { $0.asDictionary() },
      "isFinal": isFinal,
    ])
  }

  func speechToTextControllerDidFail(_ error: SpeechToTextError) {
    guard hasObservers else { return }
    sendEvent(errorEvent, ["code": error.code.rawValue, "message": error.message])
  }
}
