## 1.1.0 - 2026-06-16

### Added
- `AudioRouteResult` and `AudioRouteStatus` models.
- Call session lifecycle and verified route selection methods to the platform interface.

## 1.0.0

* Initial stable release of the platform interface package.
* Defines the common interface contract `VoipAudioRouteManagerPlatform` for audio routing management.
* Exposes `AudioOutputDevice` and `AudioOutputType` models used across all platform implementations.
* Adds support for optional `deviceId` parameter in `selectAudioOutput()` to specify initial preferred output selection.
