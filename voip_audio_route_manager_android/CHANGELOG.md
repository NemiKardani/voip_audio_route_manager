## 1.1.0 - 2026-06-17

### Added
- Native call session lifecycle handling for Android voice communication mode and audio focus.
- Verified route selection results and explicit route clearing via `clearCommunicationDevice()` on Android 12+.
- `AudioDeviceCallback` listener to stream real OS-level route changes to the platform channel.

### Fixed
- Fixed `switchToSpeaker()` silently failing when the app is launched from a terminated state via `flutter_callkit_incoming` (FCM inbound call scenario).
- Replaced deprecated `setSpeakerphoneOn()` with `AudioManager.setCommunicationDevice()` on Android 12+ (API 31+) for reliable speaker routing.
- Set `AudioManager` mode to `MODE_IN_COMMUNICATION` before initiating any route changes.
- Properly requested `AudioFocusRequest` with `USAGE_VOICE_COMMUNICATION` to ensure system routing works as expected.

## 1.0.0

* Initial stable release of the Android implementation package.
* Implements Android-specific audio output device routing via the AudioManager API.
* Adds support for Bluetooth SCO, Bluetooth LE Audio, wired headsets, and built-in speaker/receiver outputs.
* Integrates Android 12+ `setCommunicationDevice` APIs with robust fallback mechanisms for older Android versions.
