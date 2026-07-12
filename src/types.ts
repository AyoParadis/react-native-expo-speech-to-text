export enum SpeechToTextMode {
  Single = 'single',
  Continuous = 'continuous',
}

export enum SpeechToTextErrorCode {
  SpeechRecognizerNotAvailable = 'ERR_SPEECH_RECOGNIZER_NOT_AVAILABLE',
  RecordingStartFailed = 'ERR_RECORDING_START_FAILED',
  RecognitionFailed = 'ERR_RECOGNITION_FAILED',
  CleanupUnavailable = 'ERR_CLEANUP_UNAVAILABLE',
  ModelNotReady = 'ERR_MODEL_NOT_READY',
  PermissionDenied = 'ERR_PERMISSION_DENIED',
  PermissionRestricted = 'ERR_PERMISSION_RESTRICTED',
  PermissionNotDetermined = 'ERR_PERMISSION_NOT_DETERMINED',
  InvalidState = 'ERR_INVALID_STATE',
  NativeModuleOutdated = 'ERR_NATIVE_MODULE_OUTDATED',
  Unknown = 'ERR_UNKNOWN',
}

export enum SpeechToTextPermissionStatus {
  Granted = 'granted',
  Denied = 'denied',
  Restricted = 'restricted',
  Undetermined = 'undetermined',
}

export enum SpeechToTextCleanupStatus {
  Disabled = 'disabled',
  Pending = 'pending',
  Available = 'available',
  ModelNotReady = 'model-not-ready',
  UnsupportedDevice = 'unsupported-device',
  UnsupportedLocale = 'unsupported-locale',
  Unavailable = 'unavailable',
  Failed = 'failed',
}

export enum SpeechToTextTranscriptionCapability {
  Enhanced = 'enhanced',
  Basic = 'basic',
  Unavailable = 'unavailable',
}

export enum SpeechToTextModelAssetStatus {
  Ready = 'ready',
  Downloadable = 'downloadable',
  Downloading = 'downloading',
  Unavailable = 'unavailable',
}

export enum SpeechToTextCleanupStyle {
  Dictation = 'dictation',
  Note = 'note',
  Message = 'message',
}

export interface SpeechToTextCapabilities {
  transcription: SpeechToTextTranscriptionCapability;
  cleanup: SpeechToTextCleanupStatus;
  modelAssets: SpeechToTextModelAssetStatus;
  onDeviceOnly: boolean;
  supportedLocale: string | null;
}

export interface SpeechToTextTranscriptSegment {
  text: string;
  startMs?: number;
  endMs?: number;
  confidence?: number;
}

export interface SpeechToTextStartListeningOptions {
  locale?: string;
  mode?: SpeechToTextMode;
  silenceTimeoutMs?: number;
  enablePartialResults?: boolean;
  enableCleanup?: boolean;
  cleanupStyle?: SpeechToTextCleanupStyle;
}

export interface NormalizedSpeechToTextOptions extends Required<SpeechToTextStartListeningOptions> {
  requireOnDevice: true;
}

export interface SpeechToTextState {
  available: boolean;
  listening: boolean;
  ready: boolean;
  stopping: boolean;
  transcript: string | null;
  rawTranscript: string | null;
  cleanedTranscript: string | null;
  cleanupStatus: SpeechToTextCleanupStatus;
  engine: string | null;
  capabilities: SpeechToTextCapabilities;
  segments: SpeechToTextTranscriptSegment[];
  isFinal: boolean;
  permissionStatus: SpeechToTextPermissionStatus;
  lastError: SpeechToTextError | null;
}

export class SpeechToTextError extends Error {
  code: SpeechToTextErrorCode;
  details?: unknown;

  constructor(message: string, code: SpeechToTextErrorCode, details?: unknown) {
    super(message);
    this.name = 'SpeechToTextError';
    this.code = code;
    this.details = details;
  }
}

export interface SpeechToTextHookResult extends SpeechToTextState {
  refreshPermissions(): Promise<SpeechToTextPermissionStatus>;
  requestPermissions(): Promise<SpeechToTextPermissionStatus>;
  getCapabilities(): Promise<SpeechToTextCapabilities>;
  prepareOnDeviceModels(
    options?: SpeechToTextStartListeningOptions
  ): Promise<SpeechToTextCapabilities>;
  getSupportedLocales(): Promise<string[]>;
  startListening(): Promise<void>;
  stopListening(): Promise<void>;
  resetTranscript(): void;
}
