# voip_audio_route_manager_macos

The macOS implementation package of the federated plugin `voip_audio_route_manager`.

This package provides macOS-specific native platform integration using Swift Package Manager and `AVFoundation` framework interfaces to query available output hardware devices, listen to connection states, and switch active audio output routes.

## Usage

This package is **not intended to be used directly** by application developers. The main client package `voip_audio_route_manager` will automatically import and register this macOS implementation when running on macOS machines.

To install the main package, add:

```yaml
dependencies:
  voip_audio_route_manager: ^0.0.1
```

## Entitlements Setup

If your macOS application uses App Sandbox, ensure you enable the client audio-input/output permission in your `.entitlements` configuration:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```
