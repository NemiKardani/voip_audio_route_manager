## 1.1.2 - 2026-07-06

### Breaking Changes
- **iOS & macOS**: Device `id` formats have changed to stable native UID strings.
  - **iOS**: Changed device `id` from Swift's unstable, randomly-seeded `String.hashValue` (which was returned as a string representation of an integer) to the stable native `AVAudioSession` port UID string (e.g., `"speaker"`, `"receiver"`, or input UID).
  - **macOS**: Changed device `id` from a string representation of the transient `AudioDeviceID` (e.g., `"71"`) to the stable native CoreAudio device UID string.

### Changed
- iOS & macOS: Migrated CocoaPods podspec to use Swift Package Manager (SPM) source paths (`Sources/` directory), unifying the source structure and removing legacy `Classes/` directory.

### Fixed
- iOS: Fixed automatic earpiece routing by disallowing Bluetooth (removing category options) and explicitly selecting `builtInMic` as preferred input.
- iOS: Dispatched AVAudioSession route and interruption notification handlers to the main thread to ensure thread safety.
- iOS: Resets preferred device states and overrides output audio port to `.none` / sets preferred input to `nil` when starting a VoIP call session.
- iOS: Restricted built-in receiver availability in `getAvailableDevices` to only show when no external device is connected, or when it is the active route.

## 1.1.1 - 2026-06-22

### Fixed
- iOS: Automatically detect active CallKit or WebRTC sessions and bypass native `setActive(true/false)` calls to prevent conflicts and call disconnects.
- iOS: Prevent `clearAudioRoute` from deactivating the active call session.
- iOS: Synchronized Swift Package Manager (SPM) and CocoaPods implementations to resolve missing methods.

## 1.1.0 - 2026-06-17

### Added
- VoIP call session lifecycle APIs: `startCallSession()` and `endCallSession()`.
- Verified route selection APIs returning `AudioRouteResult`.
- `clearAudioRoute()` to release explicit route requests and properly tear down audio sessions when calls end.
- `getAvailableRoutes()` — query currently available audio output devices before switching.
- `onRouteChanged` stream — reactive stream for OS-level audio route changes.
- `AudioRoute` model with `AudioRouteType` enum for type-safe route handling.

### Fixed
- Android: `switchToSpeaker()` silently failing when app launched from terminated state via `flutter_callkit_incoming` (FCM inbound call scenario).
- Android 12+ (API 31+): Replaced deprecated `setSpeakerphoneOn()` with `AudioManager.setCommunicationDevice()` for reliable speaker routing.
- Android: `AudioManager` now set to `MODE_IN_COMMUNICATION` before every route change.
- Android: `AudioFocusRequest` properly requested with `USAGE_VOICE_COMMUNICATION`.
- Both platforms: Added `AudioDeviceCallback` (Android) / `AVAudioSession` notification (iOS) so `onRouteChanged` stream reflects the real OS-level route, not the intended one.

## 1.0.0

* Initial stable, production-ready release of `voip_audio_route_manager`.
* Implements unified audio output device discovery, routing, and management for VoIP communication applications.
* Implements a federated structure with support across Android, iOS, macOS, and Web:
  * **Android**: Routing via Kotlin APIs and `AudioManager`.
  * **iOS**: AVAudioSession configuration, preferred route settings, and iPad-specific earpiece support.
  * **macOS**: Native output route discovery and management.
  * **Web**: Fully conforms to the W3C Audio Output Devices API:
    * Select audio output devices with `selectAudioOutput()` including optional `deviceId` support.
    * Automatically routes HTMLMediaElements and Web Audio `AudioContext` instances programmatically using ES6 Proxy interception and `WeakRef` tracking.
    * Resolves browser privacy issues by prompting for permissions before listing Bluetooth and other outputs.
