package expo.modules.speechtotext

import expo.modules.kotlin.exception.CodedException

internal class SpeechToTextModuleException(code: String, message: String) :
  CodedException(code, message, null)

internal object SpeechToTextErrorCodes {
  const val SPEECH_RECOGNIZER_NOT_AVAILABLE = "ERR_SPEECH_RECOGNIZER_NOT_AVAILABLE"
  const val RECORDING_START_FAILED = "ERR_RECORDING_START_FAILED"
  const val RECOGNITION_FAILED = "ERR_RECOGNITION_FAILED"
  const val PERMISSION_DENIED = "ERR_PERMISSION_DENIED"
  const val PERMISSION_RESTRICTED = "ERR_PERMISSION_RESTRICTED"
  const val PERMISSION_NOT_DETERMINED = "ERR_PERMISSION_NOT_DETERMINED"
  const val INVALID_STATE = "ERR_INVALID_STATE"
  const val UNKNOWN = "ERR_UNKNOWN"
}
