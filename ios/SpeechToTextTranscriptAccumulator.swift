import Foundation

struct SpeechToTextTranscriptAccumulator {
  private var committedSegments: [String] = []
  private var pendingSegment: String?

  mutating func reset() {
    committedSegments = []
    pendingSegment = nil
  }

  mutating func discardPending() {
    pendingSegment = nil
  }

  mutating func updatePending(_ segment: String) {
    let normalized = segment.trimmingCharacters(in: .whitespacesAndNewlines)
    pendingSegment = normalized.isEmpty ? nil : normalized
  }

  @discardableResult
  mutating func commitPending() -> Bool {
    guard let pendingSegment else {
      return false
    }

    committedSegments.append(pendingSegment)
    self.pendingSegment = nil
    return true
  }

  var preview: String? {
    normalizedTranscript(
      segments: pendingSegment.map { committedSegments + [$0] } ?? committedSegments
    )
  }

  var finalized: String? {
    normalizedTranscript(segments: committedSegments)
  }

  private func normalizedTranscript(segments: [String]) -> String? {
    let transcript = segments
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return transcript.isEmpty ? nil : transcript
  }
}
