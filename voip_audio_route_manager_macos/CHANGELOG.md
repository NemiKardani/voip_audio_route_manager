## Unreleased

* Adds verified route selection results for CoreAudio default output changes.
* Reports route clearing as unsupported because macOS routing is system-default based.

## 1.0.0

* Initial stable release of the macOS implementation package.
* Implements macOS-specific audio output device routing via Swift Package Manager and CoreAudio/AVFoundation.
* Detects connected speakers, headphones, USB audio devices, Bluetooth headsets, and external display outputs.
