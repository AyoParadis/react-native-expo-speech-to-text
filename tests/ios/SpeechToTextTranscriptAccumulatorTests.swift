import Foundation

@main
struct SpeechToTextTranscriptAccumulatorTests {
  static func main() {
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

    accumulator.reset()
    accumulator.updatePending("very")
    accumulator.commitPending()
    accumulator.updatePending("very")
    accumulator.commitPending()
    precondition(accumulator.finalized == "very very")
  }
}
