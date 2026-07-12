package expo.modules.speechtotext

internal class SpeechToTextTranscriptAccumulator {
  private val committedSegments = mutableListOf<String>()
  private var pendingSegment: String? = null

  fun reset() {
    committedSegments.clear()
    pendingSegment = null
  }

  fun updatePending(segment: String) {
    pendingSegment = normalize(segment)
  }

  fun commitPending(): Boolean {
    val nextSegment = pendingSegment
    pendingSegment = null
    if (nextSegment == null) {
      return false
    }

    committedSegments += nextSegment
    return true
  }

  fun preview(): String? {
    val segments = pendingSegment?.let { committedSegments + it } ?: committedSegments
    return segments.joinToString(" ").trim().ifEmpty { null }
  }

  fun finalized(): String? = committedSegments.joinToString(" ").trim().ifEmpty { null }

  private fun normalize(segment: String): String? = segment.trim().ifEmpty { null }
}
