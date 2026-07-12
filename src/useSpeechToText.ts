import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AppState } from 'react-native';

import ExpoSpeechToTextModule, {
  AVAILABILITY_CHANGE_EVENT,
  ERROR_EVENT,
  LISTENING_STATE_CHANGE_EVENT,
  READY_STATE_CHANGE_EVENT,
  STOPPING_STATE_CHANGE_EVENT,
  TRANSCRIPT_EVENT,
} from './ExpoSpeechToTextModule';
import {
  DEFAULT_SPEECH_TO_TEXT_STATE,
  getRequiredSpeechToTextModuleMethod,
  normalizeSpeechToTextCapabilities,
  normalizeSpeechToTextModuleErrorEvent,
  normalizeSpeechToTextOptions,
  normalizeSpeechToTextState,
  toSpeechToTextError,
} from './helpers';
import { SpeechToTextCleanupStatus, SpeechToTextErrorCode } from './types';
import type {
  SpeechToTextHookResult,
  SpeechToTextStartListeningOptions,
  SpeechToTextState,
} from './types';

const UNAVAILABLE_ERROR = new Error('ExpoSpeechToText native module is not linked');

const hasEventField = (event: object, field: string) =>
  Object.prototype.hasOwnProperty.call(event, field);

export function useSpeechToText(
  options: SpeechToTextStartListeningOptions = {}
): SpeechToTextHookResult {
  const [state, setState] = useState<SpeechToTextState>(DEFAULT_SPEECH_TO_TEXT_STATE);
  const normalizedOptions = useMemo(() => normalizeSpeechToTextOptions(options), [options]);
  const optionsRef = useRef(normalizedOptions);
  useEffect(() => {
    optionsRef.current = normalizedOptions;
  }, [normalizedOptions]);

  const syncState = useCallback(async () => {
    if (!ExpoSpeechToTextModule) {
      setState(DEFAULT_SPEECH_TO_TEXT_STATE);
      return DEFAULT_SPEECH_TO_TEXT_STATE;
    }

    try {
      const nextState = await ExpoSpeechToTextModule.getStateAsync();
      const normalizedState = normalizeSpeechToTextState(nextState);
      setState((current) => ({
        ...normalizedState,
        lastError: normalizedState.lastError ?? current.lastError,
      }));
      return normalizedState;
    } catch {
      setState((current) => ({
        ...DEFAULT_SPEECH_TO_TEXT_STATE,
        lastError: current.lastError,
      }));
      return DEFAULT_SPEECH_TO_TEXT_STATE;
    }
  }, []);

  useEffect(() => {
    if (!ExpoSpeechToTextModule) {
      const resetTimer = setTimeout(() => {
        setState(DEFAULT_SPEECH_TO_TEXT_STATE);
      }, 0);
      return () => clearTimeout(resetTimer);
    }

    let isMounted = true;
    const syncStateIfMounted = async () => {
      if (!isMounted) {
        return;
      }
      await syncState();
    };

    syncStateIfMounted();

    const availabilitySubscription = ExpoSpeechToTextModule.addListener(
      AVAILABILITY_CHANGE_EVENT,
      ({ available }) => {
        setState((current) => ({ ...current, available }));
      }
    );
    const listeningStateSubscription = ExpoSpeechToTextModule.addListener(
      LISTENING_STATE_CHANGE_EVENT,
      ({ listening }) => {
        setState((current) => ({ ...current, listening }));
      }
    );
    const readyStateSubscription = ExpoSpeechToTextModule.addListener(
      READY_STATE_CHANGE_EVENT,
      ({ ready }) => {
        setState((current) => ({ ...current, ready }));
      }
    );
    const stoppingStateSubscription = ExpoSpeechToTextModule.addListener(
      STOPPING_STATE_CHANGE_EVENT,
      ({ stopping }) => {
        setState((current) => ({ ...current, stopping }));
      }
    );
    const transcriptSubscription = ExpoSpeechToTextModule.addListener(TRANSCRIPT_EVENT, (event) => {
      const nextState = normalizeSpeechToTextState(event);
      const hasRawTranscript = hasEventField(event, 'rawTranscript');
      const hasCleanedTranscript = hasEventField(event, 'cleanedTranscript');
      const hasEngine = hasEventField(event, 'engine');
      const hasSegments = hasEventField(event, 'segments');

      setState((current) => ({
        ...current,
        transcript: nextState.transcript,
        rawTranscript: hasRawTranscript ? nextState.rawTranscript : current.rawTranscript,
        cleanedTranscript: hasCleanedTranscript
          ? nextState.cleanedTranscript
          : current.cleanedTranscript,
        cleanupStatus: nextState.cleanupStatus,
        engine: hasEngine ? nextState.engine : current.engine,
        segments: hasSegments ? nextState.segments : current.segments,
        isFinal: event.isFinal,
      }));
    });
    const errorSubscription = ExpoSpeechToTextModule.addListener(
      ERROR_EVENT,
      ({ code, message }) => {
        setState((current) => ({
          ...current,
          lastError: normalizeSpeechToTextModuleErrorEvent({ code, message }),
        }));
        syncStateIfMounted();
      }
    );
    const appStateSubscription = AppState.addEventListener('change', (nextAppState) => {
      if (nextAppState === 'active') {
        syncStateIfMounted();
      }
    });

    return () => {
      isMounted = false;
      availabilitySubscription.remove();
      listeningStateSubscription.remove();
      readyStateSubscription.remove();
      stoppingStateSubscription.remove();
      transcriptSubscription.remove();
      errorSubscription.remove();
      appStateSubscription.remove();
    };
  }, [syncState]);

  const startListening = useCallback(async () => {
    if (!ExpoSpeechToTextModule) {
      throw toSpeechToTextError({
        code: SpeechToTextErrorCode.SpeechRecognizerNotAvailable,
        message: UNAVAILABLE_ERROR.message,
      });
    }

    setState((current) => ({
      ...current,
      transcript: null,
      ready: false,
      rawTranscript: null,
      cleanedTranscript: null,
      cleanupStatus: optionsRef.current.enableCleanup
        ? DEFAULT_SPEECH_TO_TEXT_STATE.cleanupStatus
        : SpeechToTextCleanupStatus.Disabled,
      segments: [],
      isFinal: false,
      lastError: null,
    }));

    try {
      await ExpoSpeechToTextModule.startListening(optionsRef.current);
      const nextState = await ExpoSpeechToTextModule.getStateAsync();
      setState({
        ...normalizeSpeechToTextState(nextState),
        lastError: null,
      });
    } catch (error) {
      const speechToTextError = toSpeechToTextError(error);
      try {
        const nextState = await ExpoSpeechToTextModule.getStateAsync();
        setState({
          ...normalizeSpeechToTextState(nextState),
          lastError: speechToTextError,
        });
      } catch {
        setState((current) => ({
          ...current,
          lastError: speechToTextError,
        }));
      }
      throw speechToTextError;
    }
  }, []);

  const refreshPermissions = useCallback(async () => {
    if (!ExpoSpeechToTextModule) {
      throw toSpeechToTextError({
        code: SpeechToTextErrorCode.SpeechRecognizerNotAvailable,
        message: UNAVAILABLE_ERROR.message,
      });
    }

    try {
      const getPermissionStatusAsync = getRequiredSpeechToTextModuleMethod<
        () => Promise<SpeechToTextState['permissionStatus']>
      >(ExpoSpeechToTextModule, 'getPermissionStatusAsync');
      const permissionStatus = await getPermissionStatusAsync();
      setState((current) => ({
        ...current,
        permissionStatus,
        lastError: null,
      }));
      return permissionStatus;
    } catch (error) {
      const speechToTextError = toSpeechToTextError(error);
      try {
        const nextState = await syncState();
        setState((current) => ({
          ...normalizeSpeechToTextState(nextState),
          lastError: speechToTextError ?? current.lastError,
        }));
      } catch {
        setState((current) => ({
          ...current,
          lastError: speechToTextError,
        }));
      }
      throw speechToTextError;
    }
  }, [syncState]);

  const requestPermissions = useCallback(async () => {
    if (!ExpoSpeechToTextModule) {
      throw toSpeechToTextError({
        code: SpeechToTextErrorCode.SpeechRecognizerNotAvailable,
        message: UNAVAILABLE_ERROR.message,
      });
    }

    try {
      const requestPermissionsAsync = getRequiredSpeechToTextModuleMethod<
        () => Promise<SpeechToTextState['permissionStatus']>
      >(ExpoSpeechToTextModule, 'requestPermissionsAsync');
      const permissionStatus = await requestPermissionsAsync();
      setState((current) => ({
        ...current,
        permissionStatus,
        lastError: null,
      }));
      return permissionStatus;
    } catch (error) {
      const speechToTextError = toSpeechToTextError(error);
      try {
        const nextState = await syncState();
        setState((current) => ({
          ...normalizeSpeechToTextState(nextState),
          lastError: speechToTextError ?? current.lastError,
        }));
      } catch {
        setState((current) => ({
          ...current,
          lastError: speechToTextError,
        }));
      }
      throw speechToTextError;
    }
  }, [syncState]);

  const getCapabilities = useCallback(async () => {
    if (!ExpoSpeechToTextModule) {
      throw toSpeechToTextError({
        code: SpeechToTextErrorCode.SpeechRecognizerNotAvailable,
        message: UNAVAILABLE_ERROR.message,
      });
    }

    const getCapabilitiesAsync = getRequiredSpeechToTextModuleMethod<
      () => Promise<SpeechToTextState['capabilities']>
    >(ExpoSpeechToTextModule, 'getCapabilitiesAsync');
    const capabilities = normalizeSpeechToTextCapabilities(await getCapabilitiesAsync());
    setState((current) => ({ ...current, capabilities }));
    return capabilities;
  }, []);

  const getSupportedLocales = useCallback(async () => {
    if (!ExpoSpeechToTextModule) {
      throw toSpeechToTextError({
        code: SpeechToTextErrorCode.SpeechRecognizerNotAvailable,
        message: UNAVAILABLE_ERROR.message,
      });
    }

    const getSupportedLocalesAsync = getRequiredSpeechToTextModuleMethod<() => Promise<string[]>>(
      ExpoSpeechToTextModule,
      'getSupportedLocalesAsync'
    );
    return getSupportedLocalesAsync();
  }, []);

  const prepareOnDeviceModels = useCallback(
    async (nextOptions: SpeechToTextStartListeningOptions = {}) => {
      if (!ExpoSpeechToTextModule) {
        throw toSpeechToTextError({
          code: SpeechToTextErrorCode.SpeechRecognizerNotAvailable,
          message: UNAVAILABLE_ERROR.message,
        });
      }

      const prepareOnDeviceModelsAsync = getRequiredSpeechToTextModuleMethod<
        (
          options: Required<SpeechToTextStartListeningOptions>
        ) => Promise<SpeechToTextState['capabilities']>
      >(ExpoSpeechToTextModule, 'prepareOnDeviceModelsAsync');
      const capabilities = normalizeSpeechToTextCapabilities(
        await prepareOnDeviceModelsAsync(
          normalizeSpeechToTextOptions({ ...optionsRef.current, ...nextOptions })
        )
      );
      setState((current) => ({ ...current, capabilities }));
      return capabilities;
    },
    []
  );

  const stopListening = useCallback(async () => {
    if (!ExpoSpeechToTextModule) {
      throw toSpeechToTextError({
        code: SpeechToTextErrorCode.SpeechRecognizerNotAvailable,
        message: UNAVAILABLE_ERROR.message,
      });
    }

    try {
      await ExpoSpeechToTextModule.stopListening();
      const nextState = await ExpoSpeechToTextModule.getStateAsync();
      setState({
        ...normalizeSpeechToTextState(nextState),
        lastError: null,
      });
    } catch (error) {
      const speechToTextError = toSpeechToTextError(error);
      try {
        const nextState = await ExpoSpeechToTextModule.getStateAsync();
        setState({
          ...normalizeSpeechToTextState(nextState),
          lastError: speechToTextError,
        });
      } catch {
        setState((current) => ({
          ...current,
          lastError: speechToTextError,
        }));
      }
      throw speechToTextError;
    }
  }, []);

  const resetTranscript = useCallback(() => {
    setState((current) => ({
      ...current,
      transcript: null,
      ready: false,
      rawTranscript: null,
      cleanedTranscript: null,
      cleanupStatus: optionsRef.current.enableCleanup
        ? DEFAULT_SPEECH_TO_TEXT_STATE.cleanupStatus
        : SpeechToTextCleanupStatus.Disabled,
      segments: [],
      isFinal: true,
    }));
    ExpoSpeechToTextModule?.resetTranscript();
  }, []);

  return {
    ...state,
    refreshPermissions,
    requestPermissions,
    getCapabilities,
    getSupportedLocales,
    prepareOnDeviceModels,
    startListening,
    stopListening,
    resetTranscript,
  };
}
