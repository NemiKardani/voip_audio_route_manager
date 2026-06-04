# voip_audio_route_manager_android

The Android implementation package of the federated plugin `voip_audio_route_manager`.

This package provides Android-specific native platform integration using Android's `AudioManager` and communication routing APIs to list available output devices, listen to connection updates, and switch the active output route.

## Usage

This package is **not intended to be used directly** by application developers. The main client package `voip_audio_route_manager` will automatically import and register this Android implementation when running on Android devices.

To install the main package, add:

```yaml
dependencies:
  voip_audio_route_manager: ^0.0.1
```

## Android Permissions

Ensure the following permissions are present in your app's `AndroidManifest.xml` if managing Bluetooth routing:

```xml
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```
