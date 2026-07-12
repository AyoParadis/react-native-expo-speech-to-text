import { NativeModule, requireOptionalNativeModule } from 'expo';

import type {
  NormalizedSpeechToTextOptions,
  SpeechToTextCapabilities,
  SpeechToTextCleanupStatus,
  SpeechToTextPermissionStatus,
  SpeechToTextState,
} from './types';

export const AVAILABILITY_CHANGE_EVENT = 'onAvailabilityChange';
export const LISTENING_STATE_CHANGE_EVENT = 'onListeningStateChange';
export const READY_STATE_CHANGE_EVENT = 'onReadyStateChange';
export const STOPPING_STATE_CHANGE_EVENT = 'onStoppingStateChange';
export const TRANSCRIPT_EVENT = 'onTranscript';
export const ERROR_EVENT = 'onError';

type ExpoSpeechToTextEvents = {
  [AVAILABILITY_CHANGE_EVENT]: (event: { available: boolean }) => void;
  [LISTENING_STATE_CHANGE_EVENT]: (event: { listening: boolean }) => void;
  [READY_STATE_CHANGE_EVENT]: (event: { ready: boolean }) => void;
  [STOPPING_STATE_CHANGE_EVENT]: (event: { stopping: boolean }) => void;
  [TRANSCRIPT_EVENT]: (event: {
    transcript: string | null;
    rawTranscript?: string | null;
    cleanedTranscript?: string | null;
    cleanupStatus?: SpeechToTextCleanupStatus;
    engine?: string | null;
    segments?: SpeechToTextState['segments'];
    isFinal: boolean;
  }) => void;
  [ERROR_EVENT]: (event: { code: string; message: string }) => void;
};

declare class ExpoSpeechToTextModule extends NativeModule<ExpoSpeechToTextEvents> {
  getStateAsync(): Promise<SpeechToTextState>;
  getPermissionStatusAsync(): Promise<SpeechToTextPermissionStatus>;
  getCapabilitiesAsync(): Promise<SpeechToTextCapabilities>;
  prepareOnDeviceModelsAsync(
    options: NormalizedSpeechToTextOptions
  ): Promise<SpeechToTextCapabilities>;
  getSupportedLocalesAsync(): Promise<string[]>;
  requestPermissionsAsync(): Promise<SpeechToTextPermissionStatus>;
  startListening(options: NormalizedSpeechToTextOptions): Promise<void>;
  stopListening(): Promise<void>;
  resetTranscript(): void;
}

export default requireOptionalNativeModule<ExpoSpeechToTextModule>('ExpoSpeechToText');
