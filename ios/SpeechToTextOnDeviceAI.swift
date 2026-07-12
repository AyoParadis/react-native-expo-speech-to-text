import Foundation
import Speech

#if canImport(FoundationModels)
import FoundationModels
#endif

final class SpeechToTextOnDeviceAI {
  func capabilities(localeIdentifier: String) async -> SpeechToTextCapabilities {
    var transcription = SpeechToTextTranscriptionCapability.basic
    var modelAssets = SpeechToTextModelAssetStatus.unavailable
    var supportedLocale: String?

    if #available(iOS 26.0, *) {
      if let locale = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale(identifier: localeIdentifier)
      ) {
        supportedLocale = locale.identifier.replacingOccurrences(of: "_", with: "-")
        transcription = SpeechTranscriber.isAvailable ? .enhanced : .basic
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        modelAssets = await mapAssetStatus(AssetInventory.status(forModules: [transcriber]))
      }
    }

    return SpeechToTextCapabilities(
      transcription: transcription,
      cleanup: cleanupStatus(localeIdentifier: localeIdentifier),
      modelAssets: modelAssets,
      supportedLocale: supportedLocale ?? localeIdentifier
    )
  }

  func prepareModels(localeIdentifier: String) async -> SpeechToTextCapabilities {
    if #available(iOS 26.0, *) {
      if let locale = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale(identifier: localeIdentifier)
      ) {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try? await AssetInventory.assetInstallationRequest(
          supporting: [transcriber]
        ) {
          try? await request.downloadAndInstall()
        }
      }
    }

    return await capabilities(localeIdentifier: localeIdentifier)
  }

  func cleanup(
    transcript: String,
    localeIdentifier: String,
    style: SpeechToTextCleanupStyle
  ) async -> (String?, SpeechToTextCleanupStatus) {
    let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else {
      return (nil, .failed)
    }

    guard cleanupStatus(localeIdentifier: localeIdentifier) == .available else {
      return (nil, cleanupStatus(localeIdentifier: localeIdentifier))
    }

#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      do {
        let instructions = """
        You clean up voice dictation locally on this device.
        Preserve the speaker's meaning and wording.
        Fix punctuation, casing, obvious speech-recognition homophones, and repeated filler words.
        Do not add facts, advice, names, emotions, or details that are not present.
        Return only the cleaned text.
        """
        let session = LanguageModelSession(
          model: .default,
          instructions: instructions
        )
        let prompt = """
        Style: \(style.rawValue)
        Locale: \(localeIdentifier)
        Transcript:
        \(raw)
        """
        let response = try await session.respond(to: prompt)
        let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
          return (nil, .failed)
        }
        return (cleaned, .available)
      } catch {
        return (nil, .failed)
      }
    }
#endif

    return (nil, .unsupportedDevice)
  }

  private func cleanupStatus(localeIdentifier: String) -> SpeechToTextCleanupStatus {
#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      let model = SystemLanguageModel.default
      guard model.supportsLocale(Locale(identifier: localeIdentifier)) else {
        return .unsupportedLocale
      }

      switch model.availability {
      case .available:
        return .available
      case .unavailable(.deviceNotEligible):
        return .unsupportedDevice
      case .unavailable(.appleIntelligenceNotEnabled), .unavailable(.modelNotReady):
        return .modelNotReady
      @unknown default:
        return .unavailable
      }
    }
#endif

    return .unsupportedDevice
  }

  @available(iOS 26.0, *)
  private func mapAssetStatus(_ status: AssetInventory.Status) -> SpeechToTextModelAssetStatus {
    switch status {
    case .installed:
      return .ready
    case .supported:
      return .downloadable
    case .downloading:
      return .downloading
    case .unsupported:
      return .unavailable
    @unknown default:
      return .unavailable
    }
  }
}
