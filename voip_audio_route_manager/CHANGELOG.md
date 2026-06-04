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
