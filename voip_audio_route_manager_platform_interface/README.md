# voip_audio_route_manager_platform_interface

The platform interface package for the federated plugin `voip_audio_route_manager`.

This package defines the common contract, platform interfaces (`VoipAudioRouteManagerPlatform`), and unified data models (`AudioOutputDevice` and `AudioOutputType`) shared by all platform-specific implementations of `voip_audio_route_manager`.

## Usage

This package is **not intended to be used directly** by application developers. Instead, developers should install the main app-facing package:

```yaml
dependencies:
  voip_audio_route_manager: ^1.1.0
```

For platform implementation developers, you should extend `VoipAudioRouteManagerPlatform` and register your implementation subclass:

```dart
class MyPlatformImplementation extends VoipAudioRouteManagerPlatform {
  static void registerWith() {
    VoipAudioRouteManagerPlatform.instance = MyPlatformImplementation();
  }
  // Implement platform contract overrides...
}
```
