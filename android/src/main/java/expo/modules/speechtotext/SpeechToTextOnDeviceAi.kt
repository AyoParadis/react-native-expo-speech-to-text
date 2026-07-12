package expo.modules.speechtotext

import android.content.Context
import com.google.mlkit.genai.common.DownloadCallback
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.proofreading.ProofreaderOptions
import com.google.mlkit.genai.proofreading.Proofreading
import com.google.mlkit.genai.proofreading.ProofreadingRequest
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.coroutines.resume

internal class SpeechToTextOnDeviceAi(private val context: Context) {
  suspend fun getCapabilities(localeTag: String): SpeechToTextCapabilities {
    val language = mapLanguage(localeTag)
      ?: return SpeechToTextCapabilities(
        transcription = SpeechToTextTranscriptionCapability.Basic,
        cleanup = SpeechToTextCleanupStatus.UnsupportedLocale,
        modelAssets = SpeechToTextModelAssetStatus.Unavailable,
        onDeviceOnly = true,
        supportedLocale = localeTag
      )

    return try {
      val proofreader = createProofreader(language)
      val status = proofreader.checkFeatureStatus().awaitBlocking()
      proofreader.close()
      SpeechToTextCapabilities(
        transcription = SpeechToTextTranscriptionCapability.Basic,
        cleanup = mapCleanupStatus(status),
        modelAssets = mapAssetStatus(status),
        onDeviceOnly = true,
        supportedLocale = localeTag
      )
    } catch (_: Exception) {
      SpeechToTextCapabilities(
        transcription = SpeechToTextTranscriptionCapability.Basic,
        cleanup = SpeechToTextCleanupStatus.Unavailable,
        modelAssets = SpeechToTextModelAssetStatus.Unavailable,
        onDeviceOnly = true,
        supportedLocale = localeTag
      )
    }
  }

  suspend fun prepareModels(localeTag: String): SpeechToTextCapabilities {
    val language = mapLanguage(localeTag) ?: return getCapabilities(localeTag)

    return try {
      val proofreader = createProofreader(language)
      val status = proofreader.checkFeatureStatus().awaitBlocking()
      if (status == FeatureStatus.DOWNLOADABLE) {
        downloadFeature(proofreader)
      }
      val preparedStatus = proofreader.checkFeatureStatus().awaitBlocking()
      proofreader.close()
      SpeechToTextCapabilities(
        transcription = SpeechToTextTranscriptionCapability.Basic,
        cleanup = mapCleanupStatus(preparedStatus),
        modelAssets = mapAssetStatus(preparedStatus),
        onDeviceOnly = true,
        supportedLocale = localeTag
      )
    } catch (_: Exception) {
      getCapabilities(localeTag)
    }
  }

  suspend fun cleanup(
    transcript: String,
    localeTag: String,
    @Suppress("UNUSED_PARAMETER") style: SpeechToTextCleanupStyle
  ): Pair<String?, SpeechToTextCleanupStatus> {
    val raw = transcript.trim()
    if (raw.isEmpty()) {
      return null to SpeechToTextCleanupStatus.Failed
    }

    val language = mapLanguage(localeTag) ?: return null to SpeechToTextCleanupStatus.UnsupportedLocale
    val proofreader = createProofreader(language)

    return try {
      val status = proofreader.checkFeatureStatus().awaitBlocking()
      if (status != FeatureStatus.AVAILABLE) {
        return null to mapCleanupStatus(status)
      }

      val cleanedChunks = splitForProofreading(raw).map { chunk ->
        val request = ProofreadingRequest.builder(chunk).build()
        val result = proofreader.runInference(request).awaitBlocking()
        result.results.firstOrNull()?.text?.trim().takeUnless { it.isNullOrEmpty() } ?: chunk
      }
      cleanedChunks.joinToString(" ").trim().takeUnless { it.isEmpty() } to SpeechToTextCleanupStatus.Available
    } catch (_: Exception) {
      null to SpeechToTextCleanupStatus.Failed
    } finally {
      proofreader.close()
    }
  }

  private fun createProofreader(language: Int) = Proofreading.getClient(
    ProofreaderOptions.builder(context)
      .setInputType(ProofreaderOptions.InputType.VOICE)
      .setLanguage(language)
      .build()
  )

  private suspend fun downloadFeature(
    proofreader: com.google.mlkit.genai.proofreading.Proofreader
  ) = suspendCancellableCoroutine { continuation ->
    proofreader.downloadFeature(object : DownloadCallback {
      override fun onDownloadStarted(bytesToDownload: Long) = Unit

      override fun onDownloadFailed(e: GenAiException) {
        if (continuation.isActive) {
          continuation.resume(Unit)
        }
      }

      override fun onDownloadProgress(totalBytesDownloaded: Long) = Unit

      override fun onDownloadCompleted() {
        if (continuation.isActive) {
          continuation.resume(Unit)
        }
      }
    })
  }

  private fun mapLanguage(localeTag: String): Int? {
    return when (Locale.forLanguageTag(localeTag).language.lowercase(Locale.US)) {
      "en" -> ProofreaderOptions.Language.ENGLISH
      "ja" -> ProofreaderOptions.Language.JAPANESE
      "fr" -> ProofreaderOptions.Language.FRENCH
      "de" -> ProofreaderOptions.Language.GERMAN
      "it" -> ProofreaderOptions.Language.ITALIAN
      "es" -> ProofreaderOptions.Language.SPANISH
      "ko" -> ProofreaderOptions.Language.KOREAN
      else -> null
    }
  }

  private fun splitForProofreading(text: String): List<String> {
    val words = text.split(Regex("\\s+")).filter { it.isNotBlank() }
    if (words.isEmpty()) {
      return emptyList()
    }

    return words.chunked(180).map { chunk -> chunk.joinToString(" ") }
  }

  private fun mapCleanupStatus(status: Int): SpeechToTextCleanupStatus {
    return when (status) {
      FeatureStatus.AVAILABLE -> SpeechToTextCleanupStatus.Available
      FeatureStatus.DOWNLOADABLE,
      FeatureStatus.DOWNLOADING -> SpeechToTextCleanupStatus.ModelNotReady
      else -> SpeechToTextCleanupStatus.UnsupportedDevice
    }
  }

  private fun mapAssetStatus(status: Int): SpeechToTextModelAssetStatus {
    return when (status) {
      FeatureStatus.AVAILABLE -> SpeechToTextModelAssetStatus.Ready
      FeatureStatus.DOWNLOADABLE -> SpeechToTextModelAssetStatus.Downloadable
      FeatureStatus.DOWNLOADING -> SpeechToTextModelAssetStatus.Downloading
      else -> SpeechToTextModelAssetStatus.Unavailable
    }
  }
}

private suspend fun <T> ListenableFuture<T>.awaitBlocking(): T =
  withContext(Dispatchers.IO) {
    get()
  }
