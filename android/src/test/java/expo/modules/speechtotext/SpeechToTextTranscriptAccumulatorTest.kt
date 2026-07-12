package expo.modules.speechtotext

import org.junit.Assert.assertEquals
import org.junit.Test

class SpeechToTextTranscriptAccumulatorTest {
  @Test
  fun `replaces volatile partials and preserves finalized recognition cycles`() {
    val accumulator = SpeechToTextTranscriptAccumulator()

    accumulator.updatePending("This is")
    assertEquals("This is", accumulator.preview())

    accumulator.updatePending("This is a test.")
    assertEquals("This is a test.", accumulator.preview())
    accumulator.commitPending()

    accumulator.updatePending("1, 2, 3, 4, 5,")
    assertEquals(
      "This is a test. 1, 2, 3, 4, 5,",
      accumulator.preview()
    )
    accumulator.commitPending()

    accumulator.updatePending("6, 7, 8, 9, 10.")
    accumulator.commitPending()

    assertEquals(
      "This is a test. 1, 2, 3, 4, 5, 6, 7, 8, 9, 10.",
      accumulator.finalized()
    )
  }

  @Test
  fun `preserves intentional repeated words across finalized cycles`() {
    val accumulator = SpeechToTextTranscriptAccumulator()
    accumulator.updatePending("very")
    accumulator.commitPending()
    accumulator.updatePending("very")
    accumulator.commitPending()

    assertEquals("very very", accumulator.finalized())
  }
}
