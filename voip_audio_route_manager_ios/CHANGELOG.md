## 1.1.0 - 2026-06-17

### Added
- Native call session lifecycle handling for `AVAudioSession` activation/deactivation.
- Verified route selection results and explicit route clearing for preferred input/output overrides.
- Listen to `AVAudioSession.routeChangeNotification` and stream real OS-level route changes to the platform channel.

## 1.0.0

* Initial stable release of the iOS implementation package.
* Implements iOS-specific audio output device routing via Swift Package Manager and AVAudioSession overrides.
* Resolves iPad earpiece support issues and correctly filters only supported available output routes.
* Adds support for Bluetooth HFP/A2DP, AirPods, wired headsets, and built-in speaker/receiver outputs.
