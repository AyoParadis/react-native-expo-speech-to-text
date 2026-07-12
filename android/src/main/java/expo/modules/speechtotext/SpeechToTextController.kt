package expo.modules.speechtotext

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

internal class SpeechToTextController(
  private val context: Context,
  private val onAvailabilityChanged: (Boolean) -> Unit,
  private val onListeningChanged: (Boolean) -> Unit,
  private val onReadyChanged: (Boolean) -> Unit,
  private val onStoppingChanged: (Boolean) -> Unit,
  private val onTranscript: (
    transcript: String?,
    rawTranscript: String?,
    cleanedTranscript: String?,
    cleanupStatus: SpeechToTextCleanupStatus,
    engine: String?,
    segments: List<SpeechToTextTranscriptSegment>,
    isFinal: Boolean
  ) -> Unit,
  private val onError: (SpeechToTextModuleException) -> Unit
) : RecognitionListener {
  private val mainHandler = Handler(Looper.getMainLooper())
  private val coroutineScope = CoroutineScope(Dispatchers.Main)
  private val onDeviceAi = SpeechToTextOnDeviceAi(context)
  private val stopProcessingGracePeriodMs = 2000L
  private var speechRecognizer: SpeechRecognizer? = null
  private var options = SpeechToTextStartOptions()
  private var listening = false
  private var ready = false
  private var stopping = false
  private var available = checkAvailability()
  private var transcript: String? = null
  private var rawTranscript: String? = null
  private var cleanedTranscript: String? = null
  private var cleanupStatus: SpeechToTextCleanupStatus = SpeechToTextCleanupStatus.Unavailable
  private var engine: String? = null
  private var segments = emptyList<SpeechToTextTranscriptSegment>()
  private val transcriptAccumulator = SpeechToTextTranscriptAccumulator()
  private var ignoreCallbacks = false
  private var stopRequested = false
  private var cleanupGeneration = 0

  private val finalizeRunnable = Runnable { finishStopProcessing() }

  init {
    onAvailabilityChanged(available)
  }

  fun getState(): Map<String, Any?> {
    refreshAvailability()
    return mapOf(
      "available" to available,
      "listening" to listening,
      "ready" to ready,
      "stopping" to stopping,
      "transcript" to transcript,
      "rawTranscript" to rawTranscript,
      "cleanedTranscript" to cleanedTranscript,
      "cleanupStatus" to cleanupStatus.rawValue,
      "engine" to engine,
      "capabilities" to currentCapabilities().toMap(),
      "segments" to segments.map { it.toMap() },
      "isFinal" to (!listening && !stopping)
    )
  }

  fun refreshAvailability() {
    val nextAvailability = checkAvailability()
    if (available != nextAvailability) {
      available = nextAvailability
      onAvailabilityChanged(available)
    }
  }

  fun resetTranscript() {
    runOnMainThread {
      transcriptAccumulator.reset()
      setReady(false)
      transcript = null
      rawTranscript = null
      cleanedTranscript = null
      cleanupGeneration += 1
      cleanupStatus = if (options.enableCleanup) SpeechToTextCleanupStatus.Unavailable else SpeechToTextCleanupStatus.Disabled
      segments = emptyList()
      emitTranscript(null, true)
    }
  }

  fun startListening(nextOptions: SpeechToTextStartOptions) {
    if (listening) {
      return
    }

    options = nextOptions
    stopRequested = false
    setStopping(false)
    refreshAvailability()

    if (!available) {
      throw SpeechToTextModuleException(
        SpeechToTextErrorCodes.SPEECH_RECOGNIZER_NOT_AVAILABLE,
        "Speech recognition is not available on this device"
      )
    }

    resetTranscript()
    startRecognizerCycle(emitListeningChange = true)
  }

  fun stopListening() {
    if (stopping || !listening) {
      return
    }

    stopRequested = true
    setReady(false)
    setListening(false)
    setStopping(true)
    mainHandler.removeCallbacks(finalizeRunnable)
    mainHandler.postDelayed(finalizeRunnable, stopProcessingGracePeriodMs)

    try {
      speechRecognizer?.stopListening()
    } catch (_: Exception) {
      finishStopProcessing()
    }
  }

  fun invalidate() {
    runOnMainThread {
      tearDownRecognizer(setListening = true)
    }
  }

  override fun onReadyForSpeech(params: Bundle?) {
    setReady(true)
  }

  override fun onBeginningOfSpeech() {
    setReady(true)
  }

  override fun onRmsChanged(rmsdB: Float) = Unit

  override fun onBufferReceived(buffer: ByteArray?) = Unit

  override fun onEndOfSpeech() = Unit

  override fun onError(error: Int) {
    if (ignoreCallbacks) {
      return
    }

    if (stopRequested) {
      finishStopProcessing()
      return
    }

    when (error) {
      SpeechRecognizer.ERROR_NO_MATCH,
      SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
        if (options.mode == SpeechToTextMode.Continuous && !stopRequested) {
          commitPendingSegment(emitPreview = false)
          restartRecognizerCycle()
        } else {
          finishStopProcessing()
        }
      }

      SpeechRecognizer.ERROR_CLIENT -> {
        if (!listening) {
          return
        }
      }

      else -> {
        val speechToTextError = mapSpeechError(error)
        tearDownRecognizer(setListening = true)
        onError(speechToTextError)
      }
    }
  }

  override fun onResults(results: Bundle?) {
    if (ignoreCallbacks || (!listening && !stopping && !stopRequested)) {
      return
    }

    if (listening) {
      setReady(true)
    }

    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
    val bestTranscript = matches?.firstOrNull()?.trim().takeUnless { it.isNullOrEmpty() }

    if (bestTranscript != null) {
      transcriptAccumulator.updatePending(bestTranscript)
      commitPendingSegment(
        emitPreview = options.mode == SpeechToTextMode.Continuous && listening && !stopRequested
      )
    }

    if (options.mode == SpeechToTextMode.Continuous && listening && !stopRequested) {
      restartRecognizerCycle()
      return
    }

    finalizeSessionTranscript()
    tearDownRecognizer(setListening = true)
  }

  override fun onPartialResults(partialResults: Bundle?) {
    if (ignoreCallbacks || (!listening && !stopping && !stopRequested)) {
      return
    }

    val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
    val bestTranscript = matches?.firstOrNull()?.trim().takeUnless { it.isNullOrEmpty() } ?: return

    setReady(true)
    transcriptAccumulator.updatePending(bestTranscript)
    transcript = transcriptAccumulator.preview()
    segments = transcript?.let { listOf(SpeechToTextTranscriptSegment(text = it)) }.orEmpty()

    if (options.enablePartialResults) {
      emitTranscript(transcript, false)
    }
  }

  override fun onEvent(eventType: Int, params: Bundle?) = Unit

  private fun startRecognizerCycle(emitListeningChange: Boolean) {
    try {
      if (emitListeningChange) {
        setReady(false)
      }
      ignoreCallbacks = true
      destroyRecognizer()

      speechRecognizer = createRecognizer().also {
        it.setRecognitionListener(this)
      }

      val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, options.locale)
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)

        if (!options.requireOnDevice) {
          putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        }
      }

      ignoreCallbacks = false
      speechRecognizer?.startListening(intent)

      if (emitListeningChange) {
        setListening(true)
      }
    } catch (error: Exception) {
      ignoreCallbacks = false
      tearDownRecognizer(setListening = false)
      throw mapRecognizerStartupException(error)
    }
  }

  private fun restartRecognizerCycle() {
    if (!listening) {
      return
    }

    startRecognizerCycle(emitListeningChange = false)
  }

  private fun commitPendingSegment(emitPreview: Boolean) {
    mainHandler.removeCallbacks(finalizeRunnable)

    if (transcriptAccumulator.commitPending()) {
      transcript = transcriptAccumulator.finalized()
      segments = transcript?.let { listOf(SpeechToTextTranscriptSegment(text = it)) }.orEmpty()
      if (emitPreview) {
        emitTranscript(transcript, false)
      }
    }
  }

  private fun finalizeSessionTranscript() {
    val finalTranscript = transcriptAccumulator.finalized()
    if (finalTranscript == null) {
      emitTranscript(null, true)
      return
    }

    transcript = finalTranscript
    rawTranscript = finalTranscript
    cleanedTranscript = null
    cleanupGeneration += 1
    cleanupStatus = if (options.enableCleanup) SpeechToTextCleanupStatus.Pending else SpeechToTextCleanupStatus.Disabled
    segments = listOf(SpeechToTextTranscriptSegment(text = finalTranscript))
    emitTranscript(finalTranscript, true)
    processCleanupIfNeeded(finalTranscript, cleanupGeneration)
  }

  private fun finishStopProcessing() {
    commitPendingSegment(emitPreview = false)
    finalizeSessionTranscript()
    tearDownRecognizer(setListening = true)
  }

  private fun processCleanupIfNeeded(raw: String?, generation: Int) {
    val rawText = raw?.trim().takeUnless { it.isNullOrEmpty() } ?: return
    if (!options.enableCleanup) {
      cleanupStatus = SpeechToTextCleanupStatus.Disabled
      emitTranscript(transcript, true)
      return
    }

    val cleanupLocale = options.locale
    val cleanupStyle = options.cleanupStyle
    coroutineScope.launch {
      val result = onDeviceAi.cleanup(rawText, cleanupLocale, cleanupStyle)
      if (cleanupGeneration != generation || rawTranscript != rawText) {
        return@launch
      }

      cleanedTranscript = result.first?.trim().takeUnless { it.isNullOrEmpty() }
      cleanupStatus = result.second
      transcript = cleanedTranscript ?: rawText
      emitTranscript(transcript, true)
    }
  }

  private fun emitTranscript(nextTranscript: String?, isFinal: Boolean) {
    onTranscript(
      nextTranscript,
      rawTranscript,
      cleanedTranscript,
      cleanupStatus,
      engine,
      segments,
      isFinal
    )
  }

  private fun currentCapabilities(): SpeechToTextCapabilities = SpeechToTextCapabilities(
    transcription = if (available) {
      SpeechToTextTranscriptionCapability.Basic
    } else {
      SpeechToTextTranscriptionCapability.Unavailable
    },
    cleanup = cleanupStatus,
    modelAssets = SpeechToTextModelAssetStatus.Unavailable,
    onDeviceOnly = options.requireOnDevice,
    supportedLocale = options.locale
  )

  private fun tearDownRecognizer(setListening: Boolean) {
    mainHandler.removeCallbacks(finalizeRunnable)
    ignoreCallbacks = true
    destroyRecognizer()
    ignoreCallbacks = false
    stopRequested = false
    setReady(false)
    setStopping(false)

    if (setListening) {
      setListening(false)
    }
  }

  private fun destroyRecognizer() {
    speechRecognizer?.cancel()
    speechRecognizer?.destroy()
    speechRecognizer = null
  }

  private fun setListening(nextListening: Boolean) {
    if (listening == nextListening) {
      return
    }

    listening = nextListening
    onListeningChanged(listening)
  }

  private fun setReady(nextReady: Boolean) {
    if (ready == nextReady) {
      return
    }

    ready = nextReady
    onReadyChanged(ready)
  }

  private fun setStopping(nextStopping: Boolean) {
    if (stopping == nextStopping) {
      return
    }

    stopping = nextStopping
    onStoppingChanged(stopping)
  }

  private fun checkAvailability(): Boolean {
    if (!options.requireOnDevice) {
      return SpeechRecognizer.isRecognitionAvailable(context)
    }

    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
      SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
  }

  private fun createRecognizer(): SpeechRecognizer {
    if (options.requireOnDevice) {
      if (
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        !SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
      ) {
        throw UnsupportedOperationException("On-device speech recognition is not available")
      }

      engine = "android-on-device-speech-recognizer"
      return SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
    }

    engine = "android-system-speech-recognizer"
    return SpeechRecognizer.createSpeechRecognizer(context)
  }

  private fun runOnMainThread(block: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) {
      block()
      return
    }

    mainHandler.post(block)
  }

  private fun mapSpeechError(error: Int): SpeechToTextModuleException {
    return when (error) {
      SpeechRecognizer.ERROR_AUDIO -> SpeechToTextModuleException(
        SpeechToTextErrorCodes.RECORDING_START_FAILED,
        "Failed to start audio recording"
      )

      SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> SpeechToTextModuleException(
        SpeechToTextErrorCodes.PERMISSION_DENIED,
        "Speech recognition permission was denied"
      )

      SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> SpeechToTextModuleException(
        SpeechToTextErrorCodes.INVALID_STATE,
        "Speech recognition is already busy"
      )

      SpeechRecognizer.ERROR_NETWORK,
      SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
      SpeechRecognizer.ERROR_SERVER -> SpeechToTextModuleException(
        SpeechToTextErrorCodes.RECOGNITION_FAILED,
        "Failed to recognize speech"
      )

      else -> SpeechToTextModuleException(
        SpeechToTextErrorCodes.UNKNOWN,
        "An unknown speech recognition error occurred"
      )
    }
  }

  private fun mapRecognizerStartupException(error: Exception): SpeechToTextModuleException {
    return when (error) {
      is UnsupportedOperationException -> SpeechToTextModuleException(
        SpeechToTextErrorCodes.SPEECH_RECOGNIZER_NOT_AVAILABLE,
        "On-device speech recognition is not available on this device"
      )

      is SecurityException -> SpeechToTextModuleException(
        SpeechToTextErrorCodes.PERMISSION_DENIED,
        "Speech recognition permission was denied"
      )

      is IllegalStateException -> SpeechToTextModuleException(
        SpeechToTextErrorCodes.INVALID_STATE,
        "Speech recognition is already busy"
      )

      is IllegalArgumentException -> SpeechToTextModuleException(
        SpeechToTextErrorCodes.RECORDING_START_FAILED,
        "Failed to start audio recording"
      )

      else -> SpeechToTextModuleException(
        SpeechToTextErrorCodes.UNKNOWN,
        error.message ?: "An unknown speech recognition error occurred"
      )
    }
  }
}
