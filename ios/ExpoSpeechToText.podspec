require "json"

package = JSON.parse(File.read(File.join(__dir__, "..", "package.json")))

Pod::Spec.new do |s|
  s.name = "ExpoSpeechToText"
  s.version = package["version"]
  s.summary = package["description"]
  s.description = "Private, on-device speech-to-text and optional transcript cleanup for Expo."
  s.license = package["license"]
  s.author = package["author"]
  s.homepage = package["homepage"]
  s.source = { git: "https://github.com/AyoParadis/react-native-expo-speech-to-text.git", tag: s.version.to_s }
  s.platforms = {
    :ios => "16.4"
  }
  s.swift_version = "5.9"
  s.static_framework = true

  s.dependency "ExpoModulesCore"
  s.frameworks = ["Speech", "AVFoundation", "FoundationModels"]

  s.source_files = "**/*.{h,m,swift}"
  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES",
    "SWIFT_COMPILATION_MODE" => "wholemodule"
  }
end
