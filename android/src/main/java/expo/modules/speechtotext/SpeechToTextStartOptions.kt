package expo.modules.speechtotext

internal enum class SpeechToTextMode(val rawValue: String) {
  Single("single"),
  Continuous("continuous");

  companion object {
    fun fromValue(value: String?): SpeechToTextMode =
      entries.firstOrNull { it.rawValue == value } ?: Single
  }
}

internal enum class SpeechToTextCleanupStyle(val rawValue: String) {
  Dictation("dictation"),
  Note("note"),
  Message("message");

  companion object {
    fun fromValue(value: String?): SpeechToTextCleanupStyle =
      entries.firstOrNull { it.rawValue == value } ?: Dictation
  }
}

internal data class SpeechToTextStartOptions(
  val locale: String = "en-US",
  val mode: SpeechToTextMode = SpeechToTextMode.Single,
  val silenceTimeoutMs: Long = 1000L,
  val enablePartialResults: Boolean = false,
  val enableCleanup: Boolean = true,
  val cleanupStyle: SpeechToTextCleanupStyle = SpeechToTextCleanupStyle.Dictation,
  val requireOnDevice: Boolean = true
) {
  companion object {
    fun fromMap(map: Map<String, Any?>): SpeechToTextStartOptions {
      val locale = (map["locale"] as? String)?.trim().takeUnless { it.isNullOrEmpty() } ?: "en-US"
      val silenceTimeoutValue = (map["silenceTimeoutMs"] as? Number)?.toLong() ?: 1000L
      return SpeechToTextStartOptions(
        locale = locale,
        mode = SpeechToTextMode.fromValue(map["mode"] as? String),
        silenceTimeoutMs = if (silenceTimeoutValue > 0) silenceTimeoutValue else 1000L,
        enablePartialResults = map["enablePartialResults"] as? Boolean ?: false,
        enableCleanup = map["enableCleanup"] as? Boolean ?: true,
        cleanupStyle = SpeechToTextCleanupStyle.fromValue(map["cleanupStyle"] as? String),
        requireOnDevice = map["requireOnDevice"] as? Boolean ?: true
      )
    }
  }
}
