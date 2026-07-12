package expo.modules.speechtotext

internal enum class SpeechToTextCleanupStatus(val rawValue: String) {
  Disabled("disabled"),
  Pending("pending"),
  Available("available"),
  ModelNotReady("model-not-ready"),
  UnsupportedDevice("unsupported-device"),
  UnsupportedLocale("unsupported-locale"),
  Unavailable("unavailable"),
  Failed("failed")
}

internal enum class SpeechToTextTranscriptionCapability(val rawValue: String) {
  Enhanced("enhanced"),
  Basic("basic"),
  Unavailable("unavailable")
}

internal enum class SpeechToTextModelAssetStatus(val rawValue: String) {
  Ready("ready"),
  Downloadable("downloadable"),
  Downloading("downloading"),
  Unavailable("unavailable")
}

internal data class SpeechToTextCapabilities(
  val transcription: SpeechToTextTranscriptionCapability,
  val cleanup: SpeechToTextCleanupStatus,
  val modelAssets: SpeechToTextModelAssetStatus,
  val onDeviceOnly: Boolean,
  val supportedLocale: String?
) {
  fun toMap(): Map<String, Any?> = mapOf(
    "transcription" to transcription.rawValue,
    "cleanup" to cleanup.rawValue,
    "modelAssets" to modelAssets.rawValue,
    "onDeviceOnly" to onDeviceOnly,
    "supportedLocale" to supportedLocale
  )
}

internal data class SpeechToTextTranscriptSegment(
  val text: String,
  val startMs: Double? = null,
  val endMs: Double? = null,
  val confidence: Double? = null
) {
  fun toMap(): Map<String, Any?> = mapOf(
    "text" to text,
    "startMs" to startMs,
    "endMs" to endMs,
    "confidence" to confidence
  )
}
