import Foundation

@main
struct SpeechToTextTranscriptAccumulatorTests {
  static func main() {
    testPartialReplacementAndFinalizedCycleAccumulation()
    testRepeatedWordsAcrossFinalizedCycles()
    testContinuousSilenceCommitsAndRestartsWithoutFinalizing()
    testLateNonFinalResultPreservesStopWatchdog()
  }

  private static func testPartialReplacementAndFinalizedCycleAccumulation() {
    var accumulator = SpeechToTextTranscriptAccumulator()

    accumulator.updatePending("This is")
    precondition(accumulator.preview == "This is")

    accumulator.updatePending("This is a test.")
    precondition(accumulator.preview == "This is a test.")
    accumulator.commitPending()

    accumulator.updatePending("1, 2, 3, 4, 5,")
    precondition(accumulator.preview == "This is a test. 1, 2, 3, 4, 5,")
    accumulator.commitPending()

    accumulator.updatePending("6, 7, 8, 9, 10.")
    accumulator.commitPending()
    precondition(
      accumulator.finalized == "This is a test. 1, 2, 3, 4, 5, 6, 7, 8, 9, 10."
    )
  }

  private static func testRepeatedWordsAcrossFinalizedCycles() {
    var accumulator = SpeechToTextTranscriptAccumulator()
    accumulator.updatePending("very")
    accumulator.commitPending()
    accumulator.updatePending("very")
    accumulator.commitPending()
    precondition(accumulator.finalized == "very very")
  }

  private static func testContinuousSilenceCommitsAndRestartsWithoutFinalizing() {
    var accumulator = SpeechToTextTranscriptAccumulator()
    accumulator.updatePending("Your willingness to just")
    let continuousSilenceAction = SpeechToTextRecognitionLifecyclePolicy.actionAfterSilence(
      mode: .continuous,
      stopRequested: false
    )
    precondition(continuousSilenceAction == .commitPendingAndRestart)
    if continuousSilenceAction == .commitPendingAndRestart {
      accumulator.commitPending()
    }
    accumulator.updatePending("Be there for me")
    precondition(
      accumulator.preview == "Your willingness to just Be there for me"
    )
  }

  private static func testLateNonFinalResultPreservesStopWatchdog() {
    let latePartialAction = SpeechToTextRecognitionLifecyclePolicy.actionAfterNonFinalResult(
      stopRequested: true
    )
    precondition(latePartialAction == .preserveStopWatchdog)
  }
}
