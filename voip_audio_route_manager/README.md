# VoIP Audio Route Manager

A production-ready Flutter package for advanced audio output device management and routing, specifically designed for VoIP communication applications (WebRTC, SIP/VoIP, custom calling engines).

Compatible with **Android**, **iOS**, **macOS**, and **Web**.

---

## Features

- **Real-Time Detection**: Automatically monitor audio output device additions, removals, and route switches.
- **Unified Streams**: Access route updates via simple Dart Streams.
- **Intelligent Switching**: Change audio output to specific devices, by ID, by type, or by name.
- **Audio Focus**: Hook into native audio focus state changes (gained/lost).
- **VoIP Optimization**: Utilizes Android's modern `setCommunicationDevice` API (Android 12+) with legacy SCO fallback, and iOS's `AVAudioSession` output overrides and preferred inputs.
- **Clean Coexistence**: Designed to run alongside `audio_session`, `flutter_webrtc`, `sip_ua`, and custom engines without conflict.

---

## Scaffolding & Architecture

This package is designed using a **Federated Plugin Architecture** for clean decoupling and robust platform-specific logic:

- `voip_audio_route_manager`: Client app-facing package.
- `voip_audio_route_manager_platform_interface`: Contract definition.
- `voip_audio_route_manager_android`: Android implementation.
- `voip_audio_route_manager_ios`: iOS implementation.
- `voip_audio_route_manager_macos`: macOS implementation.
- `voip_audio_route_manager_web`: Web implementation.

---

## Installation

Add this dependency to your `pubspec.yaml`:

```yaml
dependencies:
  voip_audio_route_manager: ^0.0.1
```

---

## Platform Specific Setup

### Android
Add these permissions to your `AndroidManifest.xml` if you support Bluetooth devices:

```xml
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

### iOS
Configure microphone description in `Info.plist` (since VoIP category is `playAndRecord`):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access for VoIP voice calls.</string>
```

Add the preprocessor flag `AUDIO_SESSION_MICROPHONE=1` in your `Podfile` `post_install` block if using recording features alongside audio session management.

### macOS
If your app is sandboxed, ensure you enable the client audio permissions in your `.entitlements` file:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

### Web
- **Secure Context Required**: The browser's media devices API is only available in secure contexts (`https://` or `localhost`).
- **User Permission**: Device labels/names will return empty strings until the user grants permission to access media devices (e.g., microphone permission).

---

## Basic Usage

### Initialization
```dart
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';

final manager = VoipAudioRouteManager.instance;

// Optional: Enable logs in debug mode
await manager.initialize(enableLogs: true);
```

### Fetch Devices & Current Route
```dart
// Get all available output devices
final List<AudioOutputDevice> devices = await manager.availableDevices();

// Get the currently active output route
final AudioOutputDevice? currentRoute = await manager.currentAudioRoute();
```

### Listening to Streams
```dart
// Listen to all available devices list updates
manager.audioDevicesStream.listen((devices) {
  print("Available devices: $devices");
});

// Listen to active route changes
manager.onRouteChanged.listen((device) {
  print("Now playing on: ${device.name}");
});

// Listen to audio focus status (e.g. paused due to phone calls)
manager.onAudioFocusChanged.listen((focused) {
  print("Audio focus active: $focused");
});
```

### Switching Routes
```dart
// Switch by device object
await manager.setAudioRoute(device);

// Switch by ID
await manager.setAudioRouteById("device_id_here");

// Switch by device type
await manager.setAudioRouteType(AudioOutputType.speaker);

// Switch by name (matches substring case-insensitively)
await manager.setAudioRouteByName("AirPods Pro");
```

---

## Integration Guides

### 1. Integrating with `flutter_webrtc`
WebRTC manages its own input/output track states. When using `voip_audio_route_manager` alongside WebRTC:

```dart
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';

// Switch output route
Future<void> switchToWebRTCDevice(AudioOutputDevice device) async {
  final manager = VoipAudioRouteManager.instance;
  
  if (Theme.of(context).platform == TargetPlatform.iOS || 
      Theme.of(context).platform == TargetPlatform.android) {
    // Mobile OS handles routing globally via AudioManager/AVAudioSession
    await manager.setAudioRoute(device);
  } else {
    // On Web/Desktop, apply the selected device ID to Helper/HTML video elements
    // e.g. for web elements:
    await Helper.selectAudioOutput(device.id);
  }
}
```

### 2. Integrating with `audio_session`
If your app uses `audio_session`, configure `audio_session` first before calling `voip_audio_route_manager`:

```dart
import 'package:audio_session/audio_session.dart';
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';

Future<void> setupAudio() async {
  // Configure audio_session first
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
    avAudioSessionMode: AVAudioSessionMode.voiceChat,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      usage: AndroidAudioUsage.voiceCommunication,
    ),
  ));
  
  // Now initialize our manager
  await VoipAudioRouteManager.instance.initialize(enableLogs: true);
}
```

### 3. Integrating with `sip_ua`
To toggle speakerphone inside a SIP session:

```dart
import 'package:sip_ua/sip_ua.dart';
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';

class CallStateListener implements SipUaHelperListener {
  final _audioManager = VoipAudioRouteManager.instance;

  @override
  void callStateChanged(Call call, CallState state) {
    if (state.state == CallStateEnum.CONFIRMED) {
      // Switch default to receiver or bluetooth
      _audioManager.setAudioRouteType(AudioOutputType.receiver);
    }
  }

  void toggleSpeaker(bool enabled) {
    _audioManager.setAudioRouteType(
      enabled ? AudioOutputType.speaker : AudioOutputType.receiver
    );
  }
}
```
