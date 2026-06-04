# voip_audio_route_manager_ios

The iOS implementation package of the federated plugin `voip_audio_route_manager`.

This package provides iOS-specific native platform integration using Swift Package Manager and `AVAudioSession` configuration options to list available output ports, handle route selections, and manage Bluetooth/AirPods output redirects.

## Usage

This package is **not intended to be used directly** by application developers. The main client package `voip_audio_route_manager` will automatically import and register this iOS implementation when running on iOS devices.

To install the main package, add:

```yaml
dependencies:
  voip_audio_route_manager: ^0.0.1
```

## iOS Setup

Configure the microphone description in your app's `Info.plist` (since VoIP call audio requires the recording category option):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access for VoIP voice calls.</string>
```
