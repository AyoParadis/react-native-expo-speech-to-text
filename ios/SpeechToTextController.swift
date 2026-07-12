import AVFoundation
import Foundation
import Speech

enum SpeechToTextMode: String {
  case single
  case continuous
}

struct SpeechToTextStartOptions {
  let locale: String
  let mode: SpeechToTextMode
  let silenceTimeoutMs: Double
  let enablePartialResults: Bool
  let enableCleanup: Bool
  let cleanupStyle: SpeechToTextCleanupStyle

  init(options: [String: Any]) {
    locale = (options["locale"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? (options["locale"] as? String ?? "en-US")
      : "en-US"
    mode = SpeechToTextMode(rawValue: options["mode"] as? String ?? "") ?? .single
    let silenceTimeout = options["silenceTimeoutMs"] as? Double ?? 1000
    silenceTimeoutMs = silenceTimeout > 0 ? silenceTimeout : 1000
    enablePartialResults = options["enablePartialResults"] as? Bool ?? false
    enableCleanup = options["enableCleanup"] as? Bool ?? true
    cleanupStyle = SpeechToTextCleanupStyle(
      rawValue: options["cleanupStyle"] as? String ?? ""
    ) ?? .dictation
  }
}

protocol SpeechToTextControllerDelegate: AnyObject {
  func speechToTextControllerDidChangeAvailability(_ available: Bool)
  func speechToTextControllerDidChangeListening(_ listening: Bool)
  func speechToTextControllerDidChangeReady(_ ready: Bool)
  func speechToTextControllerDidChangeStopping(_ stopping: Bool)
  func speechToTextControllerDidUpdateTranscript(
    _ transcript: String?,
    rawTranscript: String?,
    cleanedTranscript: String?,
    cleanupStatus: SpeechToTextCleanupStatus,
    engine: String?,
    segments: [SpeechToTextTranscriptSegment],
    isFinal: Bool
  )
  func speechToTextControllerDidFail(_ error: SpeechToTextError)
}

final class SpeechToTextController: NSObject, SFSpeechRecognizerDelegate {
  private struct AudioSessionConfiguration {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
  }

  weak var delegate: SpeechToTextControllerDelegate?

  private var speechRecognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var audioEngine: AVAudioEngine?
  private var finalizationTimer: Timer?
  private var transcriptAccumulator = SpeechToTextTranscriptAccumulator()
  private(set) var transcript: String?
  private(set) var rawTranscript: String?
  private(set) var cleanedTranscript: String?
  private(set) var cleanupStatus: SpeechToTextCleanupStatus = .unavailable
  private(set) var engine: String? = "apple-speech-recognizer"
  private(set) var segments: [SpeechToTextTranscriptSegment] = []
  private(set) var listening = false {
    didSet {
      guard oldValue != listening else { return }
      delegate?.speechToTextControllerDidChangeListening(listening)
    }
  }

  private(set) var ready = false {
    didSet {
      guard oldValue != ready else { return }
      delegate?.speechToTextControllerDidChangeReady(ready)
    }
  }

  private(set) var stopping = false {
    didSet {
      guard oldValue != stopping else { return }
      delegate?.speechToTextControllerDidChangeStopping(stopping)
    }
  }

  private(set) var available = false {
    didSet {
      guard oldValue != available else { return }
      delegate?.speechToTextControllerDidChangeAvailability(available)
    }
  }

  private var currentOptions = SpeechToTextStartOptions(options: [:])
  private var currentLocale = "en-US"
  private var originalAudioCategory: AVAudioSession.Category?
  private var originalAudioMode: AVAudioSession.Mode?
  private var originalAudioOptions: AVAudioSession.CategoryOptions?
  private var isStopping = false
  private var isStopRequested = false
  private var cleanupGeneration = 0
  private var recognitionGeneration = 0
  private let onDeviceAI = SpeechToTextOnDeviceAI()
  private let stopProcessingGracePeriod: TimeInterval = 2
  private let audioSessionConfigurations: [AudioSessionConfiguration] = [
    AudioSessionConfiguration(
      category: .record,
      mode: .measurement,
      options: [.duckOthers]
    ),
    AudioSessionConfiguration(
      category: .playAndRecord,
      mode: .measurement,
      options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP]
    ),
  ]

  func getState() -> [String: Any?] {
    refreshAvailability()
    return [
      "available": available,
      "listening": listening,
      "ready": ready,
      "stopping": stopping,
      "transcript": transcript,
      "rawTranscript": rawTranscript,
      "cleanedTranscript": cleanedTranscript,
      "cleanupStatus": cleanupStatus.rawValue,
      "engine": engine,
      "capabilities": currentCapabilities().asDictionary(),
      "segments": segments.map { $0.asDictionary() },
      "isFinal": !listening && !stopping,
      "permissionStatus": getPermissionStatus().rawValue,
      "lastError": nil,
    ]
  }

  func getCapabilities(completion: @escaping ([String: Any?]) -> Void) {
    Task {
      let capabilities = await self.onDeviceAI.capabilities(localeIdentifier: self.currentLocale)
      DispatchQueue.main.async {
        completion(capabilities.asDictionary())
      }
    }
  }

  func prepareOnDeviceModels(
    options: [String: Any],
    completion: @escaping ([String: Any?]) -> Void
  ) {
    let parsedOptions = SpeechToTextStartOptions(options: options)
    Task {
      let capabilities = await self.onDeviceAI.prepareModels(
        localeIdentifier: parsedOptions.locale
      )
      DispatchQueue.main.async {
        completion(capabilities.asDictionary())
      }
    }
  }

  func getSupportedLocales() -> [String] {
    SFSpeechRecognizer.supportedLocales()
      .map { locale in locale.identifier.replacingOccurrences(of: "_", with: "-") }
      .sorted()
  }

  func requestPermissions(completion: @escaping (SpeechToTextPermissionStatus) -> Void) {
    DispatchQueue.main.async {
      let currentStatus = self.getPermissionStatus()
      guard currentStatus == .undetermined else {
        completion(currentStatus)
        return
      }

      self.requestPermissionsInternal { _ in
        completion(self.getPermissionStatus())
      }
    }
  }

  func refreshAvailability() {
#if targetEnvironment(simulator)
    available = false
#else
    if speechRecognizer == nil {
      configureRecognizer(for: currentLocale)
    }
    available = speechRecognizer?.isAvailable ?? false
#endif
  }

  func resetTranscript() {
    if !Thread.isMainThread {
      DispatchQueue.main.async {
        self.resetTranscript()
      }
      return
    }

    transcriptAccumulator.reset()
    ready = false
    transcript = nil
    rawTranscript = nil
    cleanedTranscript = nil
    cleanupGeneration += 1
    cleanupStatus = currentOptions.enableCleanup ? .unavailable : .disabled
    segments = []
    emitTranscript(nil, isFinal: true)
  }

  func startListening(
    options: [String: Any],
    completion: @escaping (Result<Void, SpeechToTextError>) -> Void
  ) {
    DispatchQueue.main.async {
      let parsedOptions = SpeechToTextStartOptions(options: options)
      self.currentOptions = parsedOptions

      if self.listening {
        completion(.success(()))
        return
      }

      self.isStopRequested = false
      self.stopping = false
      self.configureRecognizer(for: parsedOptions.locale)
      self.refreshAvailability()

      guard self.available, self.speechRecognizer != nil else {
        completion(.failure(.speechRecognizerNotAvailable))
        return
      }

      let permissionStatus = self.getPermissionStatus()
      guard permissionStatus == .granted else {
        completion(.failure(self.permissionError(for: permissionStatus)))
        return
      }

      do {
        self.resetTranscript()
        try self.beginRecognitionCycle()
        completion(.success(()))
      } catch let speechToTextError as SpeechToTextError {
        completion(.failure(speechToTextError))
      } catch {
        completion(.failure(.unknown(message: error.localizedDescription)))
      }
    }
  }

  func stopListening() {
    DispatchQueue.main.async {
      if self.stopping {
        return
      }

      guard self.listening else {
        return
      }

      self.beginStopProcessing()
    }
  }

  func invalidate() {
    DispatchQueue.main.async {
      self.tearDownRecognitionSession(setListening: true)
    }
  }

  func speechRecognizer(
    _ speechRecognizer: SFSpeechRecognizer,
    availabilityDidChange available: Bool
  ) {
    self.available = available
  }

  private func configureRecognizer(for localeIdentifier: String) {
    currentLocale = localeIdentifier
    speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    speechRecognizer?.delegate = self
  }

  func getPermissionStatus() -> SpeechToTextPermissionStatus {
    let speechStatus = SFSpeechRecognizer.authorizationStatus()
    let microphoneStatus = AVAudioSession.sharedInstance().recordPermission

    if speechStatus == .denied || microphoneStatus == .denied {
      return .denied
    }

    if speechStatus == .restricted {
      return .restricted
    }

    if speechStatus == .authorized && microphoneStatus == .granted {
      return .granted
    }

    return .undetermined
  }

  private func requestPermissionsInternal(
    completion: @escaping (Result<Void, SpeechToTextError>) -> Void
  ) {
    requestSpeechPermission { speechResult in
      switch speechResult {
      case .failure(let error):
        completion(.failure(error))
      case .success:
        self.requestMicrophonePermission(completion: completion)
      }
    }
  }

  private func permissionError(for status: SpeechToTextPermissionStatus) -> SpeechToTextError {
    switch status {
    case .granted:
      return .invalidState
    case .denied:
      return .permissionDenied
    case .restricted:
      return .permissionRestricted
    case .undetermined:
      return .permissionNotDetermined
    }
  }

  private func requestSpeechPermission(
    completion: @escaping (Result<Void, SpeechToTextError>) -> Void
  ) {
    let status = SFSpeechRecognizer.authorizationStatus()

    switch status {
    case .authorized:
      completion(.success(()))
    case .denied:
      completion(.failure(.permissionDenied))
    case .restricted:
      completion(.failure(.permissionRestricted))
    case .notDetermined:
      SFSpeechRecognizer.requestAuthorization { newStatus in
        DispatchQueue.main.async {
          switch newStatus {
          case .authorized:
            completion(.success(()))
          case .denied:
            completion(.failure(.permissionDenied))
          case .restricted:
            completion(.failure(.permissionRestricted))
          case .notDetermined:
            completion(.failure(.permissionNotDetermined))
          @unknown default:
            completion(.failure(.unknown(message: "Unknown speech permission status")))
          }
        }
      }
    @unknown default:
      completion(.failure(.unknown(message: "Unknown speech permission status")))
    }
  }

  private func requestMicrophonePermission(
    completion: @escaping (Result<Void, SpeechToTextError>) -> Void
  ) {
    let audioSession = AVAudioSession.sharedInstance()

    switch audioSession.recordPermission {
    case .granted:
      completion(.success(()))
    case .denied:
      completion(.failure(.permissionDenied))
    case .undetermined:
      audioSession.requestRecordPermission { granted in
        DispatchQueue.main.async {
          completion(granted ? .success(()) : .failure(.permissionDenied))
        }
      }
    @unknown default:
      completion(.failure(.unknown(message: "Unknown microphone permission status")))
    }
  }

  private func beginRecognitionCycle() throws {
    guard let recognizer = speechRecognizer else {
      throw SpeechToTextError.speechRecognizerNotAvailable
    }

    cancelTimer()
    isStopping = false
    transcriptAccumulator.discardPending()
    recognitionGeneration += 1
    let currentGeneration = recognitionGeneration
    tearDownRecognitionArtifacts()

    let audioSession = AVAudioSession.sharedInstance()
    if originalAudioCategory == nil {
      originalAudioCategory = audioSession.category
      originalAudioMode = audioSession.mode
      originalAudioOptions = audioSession.categoryOptions
    }

    try configureAudioSessionForRecognition(audioSession)

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    if #available(iOS 13.0, *) {
      request.requiresOnDeviceRecognition = true
    }
    recognitionRequest = request

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      DispatchQueue.main.async {
        self?.handleRecognitionResult(
          result,
          error: error,
          generation: currentGeneration
        )
      }
    }

    let audioEngine = AVAudioEngine()
    self.audioEngine = audioEngine
    let inputNode = audioEngine.inputNode
    let recordingFormat = try resolveRecordingFormat(for: inputNode)
    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
      [weak self] buffer, _ in
      self?.recognitionRequest?.append(buffer)
    }

    audioEngine.prepare()

    do {
      try audioEngine.start()
      ready = true
      listening = true
      stopping = false
    } catch {
      tearDownRecognitionSession(setListening: false)
      throw SpeechToTextError.recordingStartFailed(
        message: "Failed to start audio recording: \(error.localizedDescription)"
      )
    }
  }

  private func handleRecognitionResult(
    _ result: SFSpeechRecognitionResult?,
    error: Error?,
    generation: Int
  ) {
    guard generation == recognitionGeneration else {
      return
    }

    if let error {
      handleRecognitionFailure(error)
      return
    }

    guard let result else {
      return
    }

    let bestTranscript = result.bestTranscription.formattedString
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !bestTranscript.isEmpty else {
      return
    }

    transcriptAccumulator.updatePending(bestTranscript)
    let previewTranscript = transcriptAccumulator.preview ?? bestTranscript
    transcript = previewTranscript
    segments = previewTranscript.isEmpty
      ? []
      : [SpeechToTextTranscriptSegment(
        text: previewTranscript,
        startMs: nil,
        endMs: nil,
        confidence: nil
      )]

    if currentOptions.enablePartialResults {
      delegate?.speechToTextControllerDidUpdateTranscript(
        previewTranscript,
        rawTranscript: rawTranscript,
        cleanedTranscript: cleanedTranscript,
        cleanupStatus: cleanupStatus,
        engine: engine,
        segments: segments,
        isFinal: false
      )
    }

    if result.isFinal {
      commitPendingSegment(
        emitPreview: currentOptions.mode == .continuous && !isStopRequested
      )

      switch currentOptions.mode {
      case .single:
        finalizeSessionTranscript()
        tearDownRecognitionSession(setListening: true)
      case .continuous:
        if isStopRequested {
          finishStopProcessing()
        } else {
          do {
            try beginRecognitionCycle()
          } catch let speechToTextError as SpeechToTextError {
            tearDownRecognitionSession(setListening: true)
            delegate?.speechToTextControllerDidFail(speechToTextError)
          } catch {
            tearDownRecognitionSession(setListening: true)
            delegate?.speechToTextControllerDidFail(
              .recordingStartFailed(message: error.localizedDescription)
            )
          }
        }
      }
      return
    }

    scheduleFinalizationTimer()
  }

  private func handleRecognitionFailure(_ error: Error) {
    if isStopping {
      return
    }

    let nsError = error as NSError
    if isExpectedCancellationError(nsError) {
      if isStopRequested || stopping {
        finishStopProcessing()
      } else {
        tearDownRecognitionSession(setListening: false)
      }
      return
    }

    if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
      if currentOptions.mode == .continuous, !isStopRequested {
        commitPendingSegment(emitPreview: false)
        do {
          try beginRecognitionCycle()
          return
        } catch {
          // Fall through and surface the underlying recovery failure below.
        }
      }

      if isStopRequested {
        finishStopProcessing()
      } else {
        tearDownRecognitionSession(setListening: true)
      }
      return
    }

    let mappedError = mapRecognitionError(nsError)
    tearDownRecognitionSession(setListening: true)
    delegate?.speechToTextControllerDidFail(mappedError)
  }

  private func beginStopProcessing() {
    isStopRequested = true
    stopping = true
    ready = false
    listening = false
    pauseRecognitionInputForStop()
    scheduleStopFinalizationTimer()
  }

  private func finishStopProcessing() {
    commitPendingSegment(emitPreview: false)
    finalizeSessionTranscript()
    tearDownRecognitionSession(setListening: false)
  }

  private func pauseRecognitionInputForStop() {
    cancelTimer()
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
  }

  private func scheduleStopFinalizationTimer() {
    cancelTimer()
    finalizationTimer = Timer.scheduledTimer(
      withTimeInterval: stopProcessingGracePeriod,
      repeats: false
    ) { [weak self] _ in
      self?.finishStopProcessing()
    }
  }

  private func scheduleFinalizationTimer() {
    cancelTimer()

    if currentOptions.mode == .continuous {
      return
    }

    finalizationTimer = Timer.scheduledTimer(
      withTimeInterval: currentOptions.silenceTimeoutMs / 1000,
      repeats: false
    ) { [weak self] _ in
      guard let self else { return }
      self.commitPendingSegment(emitPreview: false)
      self.finalizeSessionTranscript()
      self.tearDownRecognitionSession(setListening: true)
    }
  }

  private func commitPendingSegment(emitPreview: Bool) {
    cancelTimer()

    guard transcriptAccumulator.commitPending() else {
      return
    }

    transcript = transcriptAccumulator.finalized
    segments = transcript.map {
      [SpeechToTextTranscriptSegment(
        text: $0,
        startMs: nil,
        endMs: nil,
        confidence: nil
      )]
    } ?? []

    if emitPreview {
      emitTranscript(transcript, isFinal: false)
    }
  }

  private func finalizeSessionTranscript() {
    guard let finalTranscript = transcriptAccumulator.finalized else {
      emitTranscript(nil, isFinal: true)
      return
    }

    cleanupGeneration += 1
    rawTranscript = finalTranscript
    cleanedTranscript = nil
    transcript = finalTranscript
    cleanupStatus = currentOptions.enableCleanup ? .pending : .disabled
    segments = [SpeechToTextTranscriptSegment(
      text: finalTranscript,
      startMs: nil,
      endMs: nil,
      confidence: nil
    )]
    emitTranscript(finalTranscript, isFinal: true)
    processCleanupIfNeeded(for: finalTranscript, generation: cleanupGeneration)
  }

  private func tearDownRecognitionSession(setListening: Bool) {
    isStopping = true
    ready = false
    cancelTimer()
    recognitionGeneration += 1
    tearDownRecognitionArtifacts()
    restoreAudioSession()

    if setListening {
      listening = false
    }

    isStopping = false
    stopping = false
    isStopRequested = false
  }

  private func tearDownRecognitionArtifacts() {
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine = nil
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionRequest = nil
    recognitionTask = nil
  }

  private func processCleanupIfNeeded(for rawTranscript: String, generation: Int) {
    guard currentOptions.enableCleanup else {
      cleanupStatus = .disabled
      emitTranscript(transcript, isFinal: true)
      return
    }

    let locale = currentLocale
    let style = currentOptions.cleanupStyle
    Task {
      let result = await self.onDeviceAI.cleanup(
        transcript: rawTranscript,
        localeIdentifier: locale,
        style: style
      )

      DispatchQueue.main.async {
        guard self.cleanupGeneration == generation,
              self.rawTranscript == rawTranscript else {
          return
        }

        let cleaned = result.0?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cleanupStatus = result.1
        if let cleaned, !cleaned.isEmpty {
          self.cleanedTranscript = cleaned
          self.transcript = cleaned
        } else {
          self.transcript = rawTranscript
        }
        self.emitTranscript(self.transcript, isFinal: true)
      }
    }
  }

  private func emitTranscript(_ transcript: String?, isFinal: Bool) {
    delegate?.speechToTextControllerDidUpdateTranscript(
      transcript,
      rawTranscript: rawTranscript,
      cleanedTranscript: cleanedTranscript,
      cleanupStatus: cleanupStatus,
      engine: engine,
      segments: segments,
      isFinal: isFinal
    )
  }

  private func currentCapabilities() -> SpeechToTextCapabilities {
    SpeechToTextCapabilities(
      transcription: available ? .basic : .unavailable,
      cleanup: cleanupStatus,
      modelAssets: .unavailable,
      supportedLocale: currentLocale
    )
  }

  private func cancelTimer() {
    finalizationTimer?.invalidate()
    finalizationTimer = nil
  }

  private func restoreAudioSession() {
    guard let originalAudioCategory,
          let originalAudioMode,
          let originalAudioOptions else {
      return
    }

    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(
        originalAudioCategory,
        mode: originalAudioMode,
        options: originalAudioOptions
      )
      try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      // Ignore restoration issues to keep teardown non-fatal.
    }

    self.originalAudioCategory = nil
    self.originalAudioMode = nil
    self.originalAudioOptions = nil
  }

  private func configureAudioSessionForRecognition(_ audioSession: AVAudioSession) throws {
    var lastError: Error?

    for configuration in audioSessionConfigurations {
      do {
        try audioSession.setCategory(
          configuration.category,
          mode: configuration.mode,
          options: configuration.options
        )
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        return
      } catch {
        lastError = error
      }
    }

    throw SpeechToTextError.recordingStartFailed(
      message: "Failed to configure audio session: \(lastError?.localizedDescription ?? "Unknown error")"
    )
  }

  private func resolveRecordingFormat(for inputNode: AVAudioInputNode) throws -> AVAudioFormat {
    let preferredFormats = [
      inputNode.outputFormat(forBus: 0),
      inputNode.inputFormat(forBus: 0),
    ]

    if let validFormat = preferredFormats.first(where: isValidAudioInputFormat) {
      return validFormat
    }

    throw SpeechToTextError.recordingStartFailed(
      message: "No valid microphone input format is available on this device right now."
    )
  }

  private func isValidAudioInputFormat(_ format: AVAudioFormat) -> Bool {
    format.channelCount > 0 && format.sampleRate > 0
  }

  private func isExpectedCancellationError(_ error: NSError) -> Bool {
    let normalizedMessage = error.localizedDescription
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    if normalizedMessage.contains("recognition request was canceled") ||
      normalizedMessage.contains("recognition request was cancelled") {
      return true
    }

    if normalizedMessage.contains("canceled") || normalizedMessage.contains("cancelled") {
      return error.domain == "kAFAssistantErrorDomain" || error.domain == "SFSpeechRecognitionErrorDomain"
    }

    return false
  }

  private func mapRecognitionError(_ error: NSError) -> SpeechToTextError {
    switch (error.domain, error.code) {
    case ("kAFAssistantErrorDomain", 1101), ("kLSRErrorDomain", 102):
      return .recognitionFailed
    case ("kAFAssistantErrorDomain", 203):
      return .speechRecognizerNotAvailable
    default:
      return .unknown(message: error.localizedDescription)
    }
  }
}
