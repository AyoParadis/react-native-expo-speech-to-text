# react-native-expo-speech-to-text

Private, on-device speech-to-text for Expo on iOS and Android.

## Install with AI

Paste this into Codex or your coding agent:

```text
Install react-native-expo-speech-to-text in this Expo React Native app. Preserve the existing app config. Add the package's config plugin with clear microphone and speech-recognition permission messages, then create a minimal useSpeechToText integration that requests permission only after a user tap, starts/stops dictation, renders transcript, and handles stopping and lastError. Use the project's package manager and Expo commands. This is a native module: do not use Expo Go; rebuild the development client for iOS and Android. Tell me exactly what you changed and which verification commands you ran.
```

## Install manually

```sh
npx expo install react-native-expo-speech-to-text
```

```json
{
  "expo": {
    "plugins": [
      [
        "react-native-expo-speech-to-text",
        {
          "microphonePermission": "Allow $(PRODUCT_NAME) to hear your dictation.",
          "speechRecognitionPermission": "Allow $(PRODUCT_NAME) to turn speech into text."
        }
      ]
    ]
  }
}
```

Rebuild the native app with `npx expo run:ios`, `npx expo run:android`, or EAS Build. Expo Go is not supported.

## Use

```tsx
import {
  SpeechToTextMode,
  SpeechToTextPermissionStatus,
  useSpeechToText,
} from "react-native-expo-speech-to-text";

export function DictationButton() {
  const speech = useSpeechToText({
    locale: "en-US",
    mode: SpeechToTextMode.Continuous,
    enablePartialResults: true,
  });

  async function toggle() {
    if (speech.listening) return speech.stopListening();

    const permission = await speech.requestPermissions();
    if (permission === SpeechToTextPermissionStatus.Granted) {
      await speech.startListening();
    }
  }

  return (
    <>
      <Button
        title={speech.stopping ? "Finishing…" : speech.listening ? "Stop" : "Speak"}
        disabled={speech.stopping}
        onPress={toggle}
      />
      <Text>{speech.transcript}</Text>
      {speech.lastError && <Text>{speech.lastError.message}</Text>}
    </>
  );
}
```

## API

`useSpeechToText(options)` returns live native state plus these actions:

| Action | Purpose |
| --- | --- |
| `requestPermissions()` | Ask for microphone/speech access after a user action. |
| `refreshPermissions()` | Re-read permission state after returning from Settings. |
| `startListening()` / `stopListening()` | Start capture or finish the current transcript. |
| `resetTranscript()` | Clear the current transcript. |
| `getSupportedLocales()` | Return best-effort BCP-47 locale tags. |
| `getCapabilities()` | Check recognition, cleanup, and model availability. |
| `prepareOnDeviceModels()` | Download supported system models when needed. |

Options:

| Option | Default | Meaning |
| --- | --- | --- |
| `locale` | `en-US` | BCP-47 recognition locale. |
| `mode` | `Single` | `Single` stops after one utterance; `Continuous` restarts until stopped. |
| `silenceTimeoutMs` | `1000` | Finalization delay in single mode. |
| `enablePartialResults` | `false` | Emit live, non-final transcript previews. |
| `enableCleanup` | `true` | Prefer optional on-device proofreading; raw text remains the fallback. |
| `cleanupStyle` | `Dictation` | Cleanup hint: `Dictation`, `Note`, or `Message`. |

Key state is `available`, `ready`, `listening`, `stopping`, `transcript`, `rawTranscript`, `cleanedTranscript`, `isFinal`, `permissionStatus`, `cleanupStatus`, `capabilities`, and `lastError`.

## Platforms and caveats

- iOS 16.4+ and Android 8/API 26+. On-device Android recognition itself requires API 31+ and a compatible recognizer.
- Recognition locale/model support varies by device. Check `available`, `getSupportedLocales()`, and `getCapabilities()` at runtime.
- Optional cleanup requires Apple Intelligence on iOS 26+, or ML Kit GenAI proofreading on a supported Android device. Android cleanup is beta and supports English, Japanese, French, German, Italian, Spanish, and Korean.
- If cleanup is unsupported or not ready, `transcript` safely falls back to `rawTranscript`; inspect `cleanupStatus` for the reason.
- Recognition and cleanup run on-device. A network connection may still be needed to download system language/model assets.
- Native iOS and Android only: no web and no Expo Go.

MIT © Paradis Code
