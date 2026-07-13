# react-native-expo-speech-to-text

Private, on-device speech-to-text for Expo on iOS and Android.

## Install with AI

Copy this prompt into your AI:

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

## Create example

Use this production-style voice-input screen to test recognition, locale switching, partial results, and transcript reset in one place.

<p align="center">
  <a href="https://raw.githubusercontent.com/AyoParadis/react-native-expo-speech-to-text/main/docs/assets/voice-input-example.png">
    <img src="https://raw.githubusercontent.com/AyoParadis/react-native-expo-speech-to-text/main/docs/assets/voice-input-example.png" alt="Voice Input example screen with language search and speech recognition controls" width="280">
  </a>
</p>

<details>
<summary><strong>Copy this prompt into your AI</strong></summary>

```text
Build a working Voice Input example screen in this Expo React Native app using react-native-expo-speech-to-text.

Use this screenshot as the visual source of truth:
https://raw.githubusercontent.com/AyoParadis/react-native-expo-speech-to-text/main/docs/assets/voice-input-example.png

Preserve the app's existing architecture, routing, package manager, and config. If needed, install react-native-expo-speech-to-text with npx expo install, add its config plugin without replacing existing plugins, and add clear microphone and speech-recognition permission messages. Install expo-localization only if the app has no reliable way to read the device locale.

Create a self-contained VoiceInputExample screen and make it easy to open from the existing app. Recreate the screenshot closely with responsive React Native primitives and Expo icons—do not depend on any private Swooni components or assets.

Visual requirements:
- Deep navy page background (#0D043F) behind a large white surface with rounded top corners and a centered gray grab handle.
- Purple "Voice Input" heading, generous whitespace, soft shadows, large rounded corners, and no outline borders on cards or buttons.
- A white test card with a circular speaker icon, "Test it!", the selected locale name, and a status pill.
- A pale lavender transcript panel that initially says "Tap record and say a short phrase."
- A wide lavender microphone button labeled "Test this language" plus a separate disabled/enabled clear button.
- A white rounded language-search field.
- Pale lavender language rows with selection indicators and chevrons. Put "Use device language" first, then alphabetize supported locales.
- Match the screenshot's purple, navy, lavender, white, and muted-gray hierarchy. Keep every touch target at least 48 points and make the layout work on iOS and Android.

Functional requirements:
- Use useSpeechToText with the selected BCP-47 locale, SpeechToTextMode.Single, and partial results enabled.
- Request permission only after the user taps the microphone button. Start listening when idle and stop when listening.
- Drive the status pill from real state: Ready, Listening, Finishing, Unavailable, or Error.
- Render live/final transcript text in the transcript panel. Keep the placeholder only while it is empty.
- Clear with resetTranscript(); disable the clear button while empty or stopping.
- Load locales with getSupportedLocales(), turn locale tags into readable language/region labels, support search, and update recognition when a row is selected.
- Default to the device locale when supported, with a safe en-US fallback.
- Show lastError accessibly without breaking the layout and prevent duplicate start/stop taps.
- Include loading, unavailable, denied-permission, and empty-locale states.

Use a native development build—this module does not work in Expo Go. Run the smallest relevant TypeScript/lint checks and explain exactly what you changed, how to open the screen, and how to test it on both iOS and Android.
```

</details>

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

---

<h2 align="center">💛 Support this project</h2>

<p align="center">
  <strong>Help keep this package reliable and up to date across Expo, iOS, and Android.</strong><br>
  <sub>Your support funds ongoing platform compatibility, maintenance, and developer documentation.</sub>
</p>

<table align="center" width="100%">
  <tr>
    <td align="center" width="33%">
      <a href="https://www.buymeacoffee.com/Ayocodes">
        <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy me a coffee" height="56">
      </a>
    </td>
    <td align="center" width="33%">
      <a href="https://www.paypal.com/donate/?business=VCJPM8B8JADKU&amp;currency_code=USD">
        <img src="https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif" alt="Donate with PayPal" height="56">
      </a>
    </td>
    <td align="center" width="33%">
      <a href="https://github.com/sponsors/AyoCodess?o=esb">
        <img src="https://img.shields.io/badge/Sponsor_on_GitHub-EA4AAA?style=for-the-badge&amp;logo=githubsponsors&amp;logoColor=white" alt="Sponsor on GitHub" height="56">
      </a>
    </td>
  </tr>
</table>
