## Unreleased

* Adds native call session lifecycle handling for AVAudioSession activation/deactivation.
* Adds verified route selection results and explicit route clearing for preferred input/output overrides.

## 1.0.0

* Initial stable release of the iOS implementation package.
* Implements iOS-specific audio output device routing via Swift Package Manager and AVAudioSession overrides.
* Resolves iPad earpiece support issues and correctly filters only supported available output routes.
* Adds support for Bluetooth HFP/A2DP, AirPods, wired headsets, and built-in speaker/receiver outputs.
