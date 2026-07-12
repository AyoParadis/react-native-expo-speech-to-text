const {
  AndroidConfig,
  createRunOncePlugin,
  withInfoPlist,
} = require("expo/config-plugins");

const pkg = require("./package.json");

const MIN_ANDROID_SDK = 26;
const MIN_IOS_VERSION = "16.4";

const withAndroidMinSdk =
  AndroidConfig.BuildProperties.createBuildGradlePropsConfigPlugin(
    [
      {
        propName: "android.minSdkVersion",
        propValueGetter: (config) => config.android?.minSdkVersion?.toString(),
      },
    ],
    "withSpeechToTextAndroidMinSdk",
  );

function maxVersion(current, minimum) {
  if (!current) return minimum;
  const currentParts = current.split(".").map(Number);
  const minimumParts = minimum.split(".").map(Number);
  const length = Math.max(currentParts.length, minimumParts.length);

  for (let index = 0; index < length; index += 1) {
    const left = currentParts[index] || 0;
    const right = minimumParts[index] || 0;
    if (left > right) return current;
    if (left < right) return minimum;
  }
  return current;
}

function withSpeechToText(config, props = {}) {
  config.android = {
    ...config.android,
    minSdkVersion: Math.max(config.android?.minSdkVersion || 0, MIN_ANDROID_SDK),
  };
  config.ios = {
    ...config.ios,
    deploymentTarget: maxVersion(config.ios?.deploymentTarget, MIN_IOS_VERSION),
  };

  config = withAndroidMinSdk(config);

  config = withInfoPlist(config, (nextConfig) => {
    nextConfig.modResults.NSMicrophoneUsageDescription =
      nextConfig.modResults.NSMicrophoneUsageDescription ||
      props.microphonePermission ||
      "Allow $(PRODUCT_NAME) to use the microphone for speech-to-text.";
    nextConfig.modResults.NSSpeechRecognitionUsageDescription =
      nextConfig.modResults.NSSpeechRecognitionUsageDescription ||
      props.speechRecognitionPermission ||
      "Allow $(PRODUCT_NAME) to transcribe speech into text.";
    return nextConfig;
  });

  return AndroidConfig.Permissions.withPermissions(config, [
    "android.permission.RECORD_AUDIO",
  ]);
}

module.exports = createRunOncePlugin(withSpeechToText, pkg.name, pkg.version);
