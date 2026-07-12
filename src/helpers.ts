import {
  SpeechToTextCleanupStatus,
  SpeechToTextCleanupStyle,
  SpeechToTextError,
  SpeechToTextErrorCode,
  SpeechToTextModelAssetStatus,
  SpeechToTextMode,
  SpeechToTextPermissionStatus,
  SpeechToTextTranscriptionCapability,
} from './types';
import type {
  NormalizedSpeechToTextOptions,
  SpeechToTextCapabilities,
  SpeechToTextStartListeningOptions,
  SpeechToTextState,
  SpeechToTextTranscriptSegment,
} from './types';

export const DEFAULT_SPEECH_TO_TEXT_CAPABILITIES: SpeechToTextCapabilities = {
  transcription: SpeechToTextTranscriptionCapability.Unavailable,
  cleanup: SpeechToTextCleanupStatus.Unavailable,
  modelAssets: SpeechToTextModelAssetStatus.Unavailable,
  onDeviceOnly: true,
  supportedLocale: null,
};

export const DEFAULT_SPEECH_TO_TEXT_STATE: SpeechToTextState = {
  available: false,
  listening: false,
  ready: false,
  stopping: false,
  transcript: null,
  rawTranscript: null,
  cleanedTranscript: null,
  cleanupStatus: SpeechToTextCleanupStatus.Unavailable,
  engine: null,
  capabilities: DEFAULT_SPEECH_TO_TEXT_CAPABILITIES,
  segments: [],
  isFinal: true,
  permissionStatus: SpeechToTextPermissionStatus.Undetermined,
  lastError: null,
};

export const DEFAULT_SPEECH_TO_TEXT_OPTIONS: NormalizedSpeechToTextOptions = {
  locale: 'en-US',
  mode: SpeechToTextMode.Single,
  silenceTimeoutMs: 1000,
  enablePartialResults: false,
  enableCleanup: true,
  cleanupStyle: SpeechToTextCleanupStyle.Dictation,
  requireOnDevice: true,
};

export function normalizeSpeechToTextOptions(
  options: SpeechToTextStartListeningOptions = {}
): NormalizedSpeechToTextOptions {
  return {
    locale: options.locale?.trim() || DEFAULT_SPEECH_TO_TEXT_OPTIONS.locale,
    mode: options.mode ?? DEFAULT_SPEECH_TO_TEXT_OPTIONS.mode,
    silenceTimeoutMs:
      options.silenceTimeoutMs && options.silenceTimeoutMs > 0
        ? options.silenceTimeoutMs
        : DEFAULT_SPEECH_TO_TEXT_OPTIONS.silenceTimeoutMs,
    enablePartialResults:
      options.enablePartialResults ?? DEFAULT_SPEECH_TO_TEXT_OPTIONS.enablePartialResults,
    enableCleanup: options.enableCleanup ?? DEFAULT_SPEECH_TO_TEXT_OPTIONS.enableCleanup,
    cleanupStyle: normalizeEnumValue(
      SpeechToTextCleanupStyle,
      options.cleanupStyle,
      DEFAULT_SPEECH_TO_TEXT_OPTIONS.cleanupStyle
    ),
    requireOnDevice: true,
  };
}

export function normalizeSpeechToTextCapabilities(
  capabilities: Partial<SpeechToTextCapabilities> | null | undefined
): SpeechToTextCapabilities {
  return {
    transcription: normalizeEnumValue(
      SpeechToTextTranscriptionCapability,
      capabilities?.transcription,
      DEFAULT_SPEECH_TO_TEXT_CAPABILITIES.transcription
    ),
    cleanup: normalizeEnumValue(
      SpeechToTextCleanupStatus,
      capabilities?.cleanup,
      DEFAULT_SPEECH_TO_TEXT_CAPABILITIES.cleanup
    ),
    modelAssets: normalizeEnumValue(
      SpeechToTextModelAssetStatus,
      capabilities?.modelAssets,
      DEFAULT_SPEECH_TO_TEXT_CAPABILITIES.modelAssets
    ),
    onDeviceOnly: capabilities?.onDeviceOnly ?? true,
    supportedLocale:
      typeof capabilities?.supportedLocale === 'string' && capabilities.supportedLocale.length > 0
        ? capabilities.supportedLocale
        : null,
  };
}

export function normalizeSpeechToTextState(
  state: Partial<SpeechToTextState> | null | undefined
): SpeechToTextState {
  const rawTranscript =
    typeof state?.rawTranscript === 'string' && state.rawTranscript.length > 0
      ? state.rawTranscript
      : null;
  const cleanedTranscript =
    typeof state?.cleanedTranscript === 'string' && state.cleanedTranscript.length > 0
      ? state.cleanedTranscript
      : null;
  const transcript =
    typeof state?.transcript === 'string' && state.transcript.length > 0
      ? state.transcript
      : (cleanedTranscript ?? rawTranscript);

  return {
    available: state?.available ?? false,
    listening: state?.listening ?? false,
    ready: state?.ready ?? state?.listening ?? false,
    stopping: state?.stopping ?? false,
    transcript,
    rawTranscript,
    cleanedTranscript,
    cleanupStatus: normalizeEnumValue(
      SpeechToTextCleanupStatus,
      state?.cleanupStatus,
      SpeechToTextCleanupStatus.Unavailable
    ),
    engine: typeof state?.engine === 'string' && state.engine.length > 0 ? state.engine : null,
    capabilities: normalizeSpeechToTextCapabilities(state?.capabilities),
    segments: normalizeSpeechToTextSegments(state?.segments),
    isFinal:
      state?.stopping === true
        ? false
        : typeof state?.isFinal === 'boolean'
          ? state.isFinal
          : state?.listening !== true,
    permissionStatus: normalizeEnumValue(
      SpeechToTextPermissionStatus,
      state?.permissionStatus,
      SpeechToTextPermissionStatus.Undetermined
    ),
    lastError: state?.lastError ? toSpeechToTextError(state.lastError) : null,
  };
}

export function createSpeechToTextNativeModuleOutdatedError(methodName?: string) {
  const methodSuffix = methodName ? ` Missing native method: ${methodName}.` : '';

  return new SpeechToTextError(
    `SpeechToText input needs an updated app build before it can run on this device. Please update or rebuild the app and try again.${methodSuffix}`,
    SpeechToTextErrorCode.NativeModuleOutdated,
    methodName ? { methodName } : undefined
  );
}

export function getRequiredSpeechToTextModuleMethod<T extends (...args: never[]) => unknown>(
  module: unknown,
  methodName: string
): T {
  const method =
    module && typeof module === 'object'
      ? (module as Record<string, unknown>)[methodName]
      : undefined;

  if (typeof method !== 'function') {
    throw createSpeechToTextNativeModuleOutdatedError(methodName);
  }

  return method.bind(module) as T;
}

export function normalizeSpeechToTextModuleErrorEvent(error: unknown) {
  return toSpeechToTextError(error);
}

export function toSpeechToTextError(error: unknown): SpeechToTextError {
  if (error instanceof SpeechToTextError) {
    return error;
  }

  const maybeError = error as {
    code?: string;
    message?: string;
    details?: unknown;
  };
  const code = normalizeEnumValue(
    SpeechToTextErrorCode,
    maybeError?.code,
    SpeechToTextErrorCode.Unknown
  );

  return new SpeechToTextError(
    maybeError?.message || 'An unknown speech recognition error occurred',
    code,
    maybeError?.details
  );
}

function normalizeEnumValue<T extends Record<string, string>>(
  enumLike: T,
  value: unknown,
  fallback: T[keyof T]
): T[keyof T] {
  const options = Object.values(enumLike) as T[keyof T][];
  return options.find((option) => option === value) ?? fallback;
}

function normalizeSpeechToTextSegments(segments: unknown): SpeechToTextTranscriptSegment[] {
  if (!Array.isArray(segments)) {
    return [];
  }

  const normalizedSegments: SpeechToTextTranscriptSegment[] = [];
  for (const segment of segments) {
    const maybeSegment = segment as Partial<SpeechToTextTranscriptSegment>;
    const text = typeof maybeSegment.text === 'string' ? maybeSegment.text.trim() : '';

    if (text.length > 0) {
      normalizedSegments.push({
        text,
        startMs: normalizeOptionalNumber(maybeSegment.startMs),
        endMs: normalizeOptionalNumber(maybeSegment.endMs),
        confidence: normalizeOptionalNumber(maybeSegment.confidence),
      });
    }
  }
  return normalizedSegments;
}

function normalizeOptionalNumber(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}
