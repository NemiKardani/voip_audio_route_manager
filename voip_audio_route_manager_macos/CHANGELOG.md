## 1.1.2 - 2026-07-06

### Changed
- Migrated CocoaPods podspec to use Swift Package Manager (SPM) source paths (`Sources/` directory) and removed legacy `Classes/` folder.

## 1.1.0 - 2026-06-16

### Added
- Verified route selection results for CoreAudio default output changes.
- Reports route clearing as unsupported because macOS routing is system-default based.

## 1.0.0

* Initial stable release of the macOS implementation package.
* Implements macOS-specific audio output device routing via Swift Package Manager and CoreAudio/AVFoundation.
* Detects connected speakers, headphones, USB audio devices, Bluetooth headsets, and external display outputs.
