import { describe, expect, it } from "vitest";
import {
	createSpeechToTextNativeModuleOutdatedError,
	getRequiredSpeechToTextModuleMethod,
	normalizeSpeechToTextModuleErrorEvent,
	normalizeSpeechToTextOptions,
	normalizeSpeechToTextState,
	toSpeechToTextError,
} from "../src/helpers";
import {
	SpeechToTextCleanupStatus,
	SpeechToTextCleanupStyle,
	SpeechToTextErrorCode,
	SpeechToTextMode,
	SpeechToTextModelAssetStatus,
	SpeechToTextPermissionStatus,
	SpeechToTextTranscriptionCapability,
} from "../src/types";

const defaultCapabilities = {
	transcription: SpeechToTextTranscriptionCapability.Unavailable,
	cleanup: SpeechToTextCleanupStatus.Unavailable,
	modelAssets: SpeechToTextModelAssetStatus.Unavailable,
	onDeviceOnly: true,
	supportedLocale: null,
};

describe("react-native-expo-speech-to-text helpers", () => {
	it("returns safe defaults before native state resolves", () => {
			expect(normalizeSpeechToTextState(undefined)).toEqual({
			available: false,
			listening: false,
			ready: false,
			stopping: false,
			transcript: null,
			rawTranscript: null,
			cleanedTranscript: null,
			cleanupStatus: SpeechToTextCleanupStatus.Unavailable,
			engine: null,
			capabilities: defaultCapabilities,
			segments: [],
			isFinal: true,
			permissionStatus: SpeechToTextPermissionStatus.Undetermined,
			lastError: null,
		});
	});

	it("preserves native stop-processing state in normalized snapshots", () => {
		expect(
			normalizeSpeechToTextState({
				available: true,
				listening: false,
				stopping: true,
				transcript: "hello",
				permissionStatus: SpeechToTextPermissionStatus.Granted,
			}),
		).toEqual({
			available: true,
			listening: false,
			ready: false,
			stopping: true,
			transcript: "hello",
			rawTranscript: null,
			cleanedTranscript: null,
			cleanupStatus: SpeechToTextCleanupStatus.Unavailable,
			engine: null,
			capabilities: defaultCapabilities,
			segments: [],
			isFinal: false,
			permissionStatus: SpeechToTextPermissionStatus.Granted,
			lastError: null,
		});
	});

	it("does not trust a final flag while native stop processing is still active", () => {
		expect(
			normalizeSpeechToTextState({
				listening: false,
				stopping: true,
				transcript: "last partial",
				isFinal: true,
			}),
		).toMatchObject({
			transcript: "last partial",
			stopping: true,
			isFinal: false,
		});
	});

	it("preserves whether a transcript update is still partial", () => {
		expect(
			normalizeSpeechToTextState({
				transcript: "we should",
				isFinal: false,
			}),
		).toMatchObject({
			transcript: "we should",
			isFinal: false,
		});
	});

	it("keeps the recorder in a preparing state until native capture is ready", () => {
		expect(
			normalizeSpeechToTextState({
				listening: true,
				ready: false,
			}),
		).toMatchObject({
			listening: true,
			ready: false,
		});
	});

	it("falls back to listening for readiness with older native snapshots", () => {
		expect(normalizeSpeechToTextState({ listening: true })).toMatchObject({
			listening: true,
			ready: true,
		});
	});

	it("normalizes start options onto the supported compatibility surface", () => {
		expect(
			normalizeSpeechToTextOptions({
				mode: SpeechToTextMode.Continuous,
				silenceTimeoutMs: 0,
			}),
		).toEqual({
			locale: "en-US",
			mode: SpeechToTextMode.Continuous,
			silenceTimeoutMs: 1000,
			enablePartialResults: false,
			enableCleanup: true,
			cleanupStyle: SpeechToTextCleanupStyle.Dictation,
			requireOnDevice: true,
		});
	});

	it("prefers cleaned transcript while preserving raw transcript", () => {
		expect(
			normalizeSpeechToTextState({
				rawTranscript: "please meat me at the bear",
				cleanedTranscript: "Please meet me at the bar.",
				cleanupStatus: SpeechToTextCleanupStatus.Available,
			}),
		).toMatchObject({
			transcript: "Please meet me at the bar.",
			rawTranscript: "please meat me at the bear",
			cleanedTranscript: "Please meet me at the bar.",
			cleanupStatus: SpeechToTextCleanupStatus.Available,
		});
	});

	it("falls back to raw transcript when cleanup is unavailable", () => {
		expect(
			normalizeSpeechToTextState({
				rawTranscript: "hello from device",
				cleanupStatus: SpeechToTextCleanupStatus.UnsupportedDevice,
			}),
		).toMatchObject({
			transcript: "hello from device",
			rawTranscript: "hello from device",
			cleanedTranscript: null,
			cleanupStatus: SpeechToTextCleanupStatus.UnsupportedDevice,
		});
	});

	it("keeps raw transcript available while cleanup is pending", () => {
		expect(
			normalizeSpeechToTextState({
				rawTranscript: "raw words from device",
				cleanupStatus: SpeechToTextCleanupStatus.Pending,
			}),
		).toMatchObject({
			transcript: "raw words from device",
			rawTranscript: "raw words from device",
			cleanedTranscript: null,
			cleanupStatus: SpeechToTextCleanupStatus.Pending,
		});
	});

	it("maps native coded errors onto stable SpeechToTextError instances", () => {
		const error = toSpeechToTextError({
			code: SpeechToTextErrorCode.PermissionDenied,
			message: "Permission denied",
		});

		expect(error.code).toBe(SpeechToTextErrorCode.PermissionDenied);
		expect(error.message).toBe("Permission denied");
	});

	it("guards missing native module methods with an outdated-build error", () => {
		expect(() =>
			getRequiredSpeechToTextModuleMethod({}, "requestPermissionsAsync"),
		).toThrowError(/updated app build/i);
	});

	it("normalizes native error events onto stable SpeechToTextError instances", () => {
		const error = normalizeSpeechToTextModuleErrorEvent({
			code: SpeechToTextErrorCode.RecognitionFailed,
			message: "Recognition failed",
		});

		expect(error.code).toBe(SpeechToTextErrorCode.RecognitionFailed);
		expect(error.message).toBe("Recognition failed");
	});

	it("creates a specific outdated-build error for stale native binaries", () => {
		const error = createSpeechToTextNativeModuleOutdatedError(
			"getPermissionStatusAsync",
		);

		expect(error.code).toBe(SpeechToTextErrorCode.NativeModuleOutdated);
		expect(error.message).toMatch(/getPermissionStatusAsync/);
	});
});
