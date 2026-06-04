## 1.0.0

* Initial stable release of the Web implementation package.
* Implements Web-specific audio output device routing via the HTML5 browser MediaDevices API.
* Resolves browser privacy issues by supporting microphone permission requests, enabling full Bluetooth and output device discovery and listing.
* Implements the W3C Audio Output Devices API (`selectAudioOutput` with optional `deviceId` support).
* Adds a dynamic tab-wide proxy interception script using ES6 Proxies and WeakRef to automatically route programmatically created `AudioContext` and `HTMLMediaElement` instances to the selected output device.
