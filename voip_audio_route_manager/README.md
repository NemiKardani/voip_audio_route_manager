<h1 align="center">VoIP Audio Route Manager</h1>

[![pub package](https://img.shields.io/pub/v/voip_audio_route_manager.svg?logo=dart&logoColor=white)](https://pub.dev/packages/voip_audio_route_manager)
[![pub points](https://img.shields.io/pub/points/voip_audio_route_manager.svg)](https://pub.dev/packages/voip_audio_route_manager/score)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios%20%7C%20macos%20%7C%20web-blue.svg)](https://pub.dev/packages/voip_audio_route_manager)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://github.com/NemiKardani/voip_audio_route_manager/actions/workflows/ci_checks.yml/badge.svg)](https://github.com/NemiKardani/voip_audio_route_manager/actions)
[![GitHub Stars](https://img.shields.io/github/stars/NemiKardani/voip_audio_route_manager.svg)](https://github.com/NemiKardani/voip_audio_route_manager/stargazers)

<p align="center">
  <b>A production-ready Flutter package for VoIP audio route switching, call audio routing, and Bluetooth audio output device management.</b>
</p>

<p align="center">
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#features">Features</a> •
  <a href="#integration-guides">Integrations</a> •
  <a href="#api-reference">API</a> •
  <a href="#faq">FAQ</a>
</p>

---

## What is VoIP Audio Route Manager?

**VoIP Audio Route Manager** is a complete Flutter audio manager and audio output device router for real-time device selection. It enables your Flutter app to **easily detect, list, and switch audio output devices** — including speakerphone, earpiece/receiver, wired headsets, and Bluetooth devices — across **Android, iOS, macOS, and Web**.

Built specifically for **VoIP communication apps** using [WebRTC](https://webrtc.org/), [SIP/VoIP](https://en.wikipedia.org/wiki/Session_Initiation_Protocol), custom calling engines, and [CallKit](https://developer.apple.com/documentation/callkit) integrations, this package solves the common problem of unreliable audio routing in real-time communication apps.

### Why Use This Package?

If you are building a **Flutter VoIP calling app**, **SIP client**, **WebRTC video/voice app**, or any Flutter application that needs a reliable **call audio route** or **VoIP audio route switch**, this package gives you a single, consistent API across all platforms — eliminating the need to write complex native platform channels yourself.

> 💡 **Problem it solves:** Native audio routing APIs differ significantly across Android (AudioManager), iOS (AVAudioSession), macOS (CoreAudio), and Web (MediaDevices). This package unifies them into one clean Dart interface.

---

## Table of Contents

- [What is VoIP Audio Route Manager?](#what-is-voip-audio-route-manager)
- [Features](#features)
- [Supported Platforms](#supported-platforms)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Basic Usage](#basic-usage)
  - [Initialization](#initialization)
  - [Fetch Devices & Current Route](#fetch-devices--current-route)
  - [Listening to Streams](#listening-to-streams)
  - [Switching Routes](#switching-routes)
  - [Verified Route Switching](#verified-route-switching)
- [Integration Guides](#integration-guides)
  - [flutter_webrtc Integration](#1-integrating-with-flutter_webrtc)
  - [audio_session Integration](#2-integrating-with-audio_session)
  - [sip_ua Integration](#3-integrating-with-sip_ua)
  - [CallKit Integration](#4-integrating-with-callkit)
- [API Reference](#api-reference)
- [Platform-Specific Behavior](#platform-specific-behavior)
- [Troubleshooting & FAQ](#troubleshooting--faq)
- [Comparison with Alternatives](#comparison-with-alternatives)
- [Contributing](#contributing)
- [Changelog](#changelog)
- [License](#license)

---

## Features

| Feature | Description |
|---------|-------------|
| 🔊 **Real-Time Detection** | Automatically monitor audio output device additions, removals, and route switches in real time. |
| 🔁 **Unified Dart Streams** | Access route updates, device list changes, and audio focus events via simple, reactive Dart Streams. |
| 🎯 **Intelligent Switching** | Change the audio output route by device ID, device type, or device name with a single method call. |
| 🎧 **Bluetooth Route Switch** | Detect and switch to/from Bluetooth headsets, earbuds, and car audio seamlessly. |
| 🔈 **Speaker / Earpiece Toggle** | One-line calls to flip between speakerphone and receiver during active calls. |
| 🎚️ **Audio Focus & Detection** | React to native audio focus state changes (gained/lost), Bluetooth connection states, and headphone plug/unplug events. |
| 📞 **Platform-Specific APIs** | Uses Android's modern [`setCommunicationDevice`](https://developer.android.com/reference/android/media/AudioManager#setCommunicationDevice(android.media.AudioDeviceInfo)) API (Android 12+) with legacy SCO fallback, iOS [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession) output overrides, macOS [CoreAudio](https://developer.apple.com/documentation/coreaudio), and the Web [MediaDevices API](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices). |
| 🤝 **Clean Coexistence** | Designed to run alongside [`audio_session`](https://pub.dev/packages/audio_session), [`flutter_webrtc`](https://pub.dev/packages/flutter_webrtc), [`sip_ua`](https://pub.dev/packages/sip_ua), and custom calling engines without conflict. |

---

## Supported Platforms

| Platform | Support | Minimum Version | Notes |
|----------|---------|-----------------|-------|
| **Android** | ✅ Full | API 21+ (Android 5.0) | Uses `setCommunicationDevice` on Android 12+, SCO fallback on older versions. |
| **iOS** | ✅ Full | iOS 11.0+ | Uses `AVAudioSession` category and mode overrides. |
| **macOS** | ✅ Full | macOS 10.14+ | Uses CoreAudio device enumeration and selection. |
| **Web** | ✅ Full | Modern browsers | Uses `MediaDevices.enumerateDevices()` and `HTMLMediaElement.setSinkId()`. |

> ⚠️ **Windows and Linux** are not yet supported. See [Issue #42](https://github.com/your-org/voip_audio_route_manager/issues/42) for progress.

---

## Installation

Add this dependency to your `pubspec.yaml`:

```yaml
dependencies:
  voip_audio_route_manager: ^1.1.0
```

Then run:

```bash
flutter pub get
```


## Quick Start

Get up and running in under 30 seconds:

```dart
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';

void main() async {
  final manager = VoipAudioRouteManager.instance;

  // 1. Initialize
  await manager.initialize(enableLogs: true);

  // 2. Start a call session
  await manager.startCallSession();

  // 3. List available devices
  final devices = await manager.availableDevices();
  print(devices);

  // 4. Switch to speakerphone
  await manager.setAudioRouteType(AudioOutputType.speaker);

  // 5. End the call session
  await manager.endCallSession();
}
```

---

## Basic Usage

### Initialization

```dart
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';

final manager = VoipAudioRouteManager.instance;

// Optional: Enable debug logs
await manager.initialize(enableLogs: true);

// Activate native VoIP audio mode/focus when a call starts
await manager.startCallSession();

// Release route/focus requests when the call ends
await manager.endCallSession();
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

// Listen to audio focus status (e.g., paused due to phone calls)
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

// Switch by name (matches substring case-insensitively) — great for Bluetooth route switch
await manager.setAudioRouteByName("AirPods Pro");
```

### Verified Route Switching

```dart
// Returns requested route, actual route, status, and diagnostics.
final AudioRouteResult result =
    await manager.selectAudioRouteType(AudioOutputType.speaker);

if (!result.success) {
  print("Route failed: ${result.status} ${result.message}");
}

// Clear explicit routing and return to platform default behavior.
await manager.clearAudioRoute();
```

---

## Integration Guides

### 1. Integrating with flutter_webrtc

[WebRTC](https://webrtc.org/) manages its own input/output track states. When using `voip_audio_route_manager` alongside `flutter_webrtc`:

```dart
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';

Future<void> switchToWebRTCDevice(AudioOutputDevice device) async {
  final manager = VoipAudioRouteManager.instance;

  if (Theme.of(context).platform == TargetPlatform.iOS ||
      Theme.of(context).platform == TargetPlatform.android) {
    // Mobile OS handles routing globally via AudioManager/AVAudioSession
    await manager.setAudioRoute(device);
  } else {
    // On Web/Desktop, apply the selected device ID to Helper/HTML video elements
    await Helper.selectAudioOutput(device.id);
  }
}
```

> 📘 See the [flutter_webrtc documentation](https://pub.dev/packages/flutter_webrtc) for more details.

### 2. Integrating with audio_session

If your app uses [`audio_session`](https://pub.dev/packages/audio_session), configure it first before calling `voip_audio_route_manager`:

```dart
import 'package:audio_session/audio_session.dart';
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';

Future<void> setupAudio() async {
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

  await VoipAudioRouteManager.instance.initialize(enableLogs: true);
}
```

> 📘 Read the [audio_session package guide](https://pub.dev/packages/audio_session) for session configuration patterns.

### 3. Integrating with sip_ua

To toggle speakerphone inside a [SIP](https://en.wikipedia.org/wiki/Session_Initiation_Protocol) session:

```dart
import 'package:sip_ua/sip_ua.dart';
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';

class CallStateListener implements SipUaHelperListener {
  final _audioManager = VoipAudioRouteManager.instance;

  @override
  void callStateChanged(Call call, CallState state) {
    if (state.state == CallStateEnum.CONFIRMED) {
      _audioManager.setAudioRouteType(AudioOutputType.receiver);
    }
  }

  void toggleSpeaker(bool enabled) {
    _audioManager.setAudioRouteType(
      enabled ? AudioOutputType.speaker : AudioOutputType.receiver,
    );
  }
}
```

> 📘 Check the [sip_ua package documentation](https://pub.dev/packages/sip_ua) for SIP session management.

### 4. Integrating with CallKit

For iOS apps using [CallKit](https://developer.apple.com/documentation/callkit), ensure your audio session is configured before reporting the call:

```dart
import 'package:call_kit/call_kit.dart';
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';

Future<void> reportIncomingCall(String uuid) async {
  await VoipAudioRouteManager.instance.startCallSession();
  // ... report call to CallKit
}
```

> 📘 Refer to [Apple's CallKit documentation](https://developer.apple.com/documentation/callkit) for full integration details.

---

## API Reference

| Method / Stream | Description |
|-----------------|-------------|
| `initialize({enableLogs})` | Initializes the manager, optionally with debug logging. |
| `startCallSession()` | Activates native VoIP audio mode/focus when a call starts. |
| `endCallSession()` | Releases route/focus requests when the call ends. |
| `availableDevices()` | Returns all currently available output devices. |
| `currentAudioRoute()` | Returns the currently active output route. |
| `setAudioRoute(device)` | Switches to a specific device object. |
| `setAudioRouteById(id)` | Switches route by device ID. |
| `setAudioRouteType(type)` | Switches route by `AudioOutputType` (speaker, receiver, bluetooth, etc.). |
| `setAudioRouteByName(name)` | Switches route by matching device name (case-insensitive substring). |
| `selectAudioRouteType(type)` | Switches route and returns a verified `AudioRouteResult` with diagnostics. |
| `clearAudioRoute()` | Clears explicit routing, returning to platform default behavior. |
| `audioDevicesStream` | Stream of available device list updates. |
| `onRouteChanged` | Stream of active route changes. |
| `onAudioFocusChanged` | Stream of audio focus gained/lost events. |

### AudioOutputDevice Model

```dart
class AudioOutputDevice {
  final String id;           // Unique device identifier
  final String name;         // Human-readable device name
  final AudioOutputType type; // Device category
}

enum AudioOutputType {
  speaker,    // Built-in loudspeaker
  receiver,   // Earpiece / phone speaker
  wired,      // 3.5mm headset or USB-C headphones
  bluetooth,  // Bluetooth headset, earbuds, or car audio
  unknown,    // Unrecognized device type
}
```

---

## Troubleshooting & FAQ

### Why is my Bluetooth device not showing up?

Ensure Bluetooth permissions are granted on Android (`BLUETOOTH_CONNECT` for API 31+). On iOS, ensure your `AVAudioSession` category options include `allowBluetooth`. On Web, ensure the user has granted microphone permissions — browsers hide device labels until permission is granted.

### Can I use this with flutter_sound or just_audio?

Yes. This package is designed to coexist with other audio packages. It manages the **audio output route** (which speaker/headset the sound comes out of), while packages like `flutter_sound` or `just_audio` manage the **audio content** (what sound is played). Initialize `voip_audio_route_manager` after configuring your primary audio package.

### Why does route switching fail on some Android devices?

Some OEMs (Samsung, Xiaomi, Huawei) customize the Android AudioManager behavior. The package includes a fallback to SCO (Bluetooth headset) routing and logs detailed diagnostics when `enableLogs: true` is set. If you encounter issues, please [open an issue](https://github.com/your-org/voip_audio_route_manager/issues) with device model and Android version.

### How do I handle audio focus during incoming phone calls?

Listen to `onAudioFocusChanged` and pause/resume your call audio accordingly. On Android, this maps to `AudioManager.AUDIOFOCUS_LOSS`. On iOS, it maps to `AVAudioSession.interruptionNotification`.

### Is this package suitable for music apps?

While technically possible, this package is optimized for **VoIP and real-time communication** use cases. For music playback apps, consider using [`audio_session`](https://pub.dev/packages/audio_session) directly for more granular audio session control.

### How does this compare to audio_session?

| Feature | `voip_audio_route_manager` | `audio_session` |
|---------|---------------------------|-----------------|
| Primary purpose | Audio output device routing | Audio session configuration |
| Bluetooth switching | ✅ Native + seamless | ⚠️ Requires manual setup |
| Platform abstraction | ✅ Unified API | ⚠️ Platform-specific config |
| WebRTC/SIP integration | ✅ Built-in guides | ❌ Not specific |
| Best for | VoIP calling apps | General audio apps |

> 💡 **Tip:** Use `audio_session` for session configuration, then `voip_audio_route_manager` for device routing.

### Does it support Windows or Linux?

Not yet. Windows and Linux support is on the [roadmap](https://github.com/your-org/voip_audio_route_manager/issues/42). For now, use conditional imports:

```dart
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart'
    if (dart.library.html) 'package:voip_audio_route_manager/voip_audio_route_manager_web.dart';
```

### How do I report a bug or request a feature?

Please [open an issue](https://github.com/your-org/voip_audio_route_manager/issues) on GitHub. Include your Flutter version, platform, and a minimal reproducible example.

---

## Comparison with Alternatives

| Package | Platforms | Bluetooth | WebRTC Ready | Maintenance |
|---------|-----------|-----------|--------------|-------------|
| **voip_audio_route_manager** | Android, iOS, macOS, Web | ✅ Full | ✅ Yes | ✅ Active |
| `audio_session` | All Flutter platforms | ⚠️ Manual | ⚠️ Partial | ✅ Active |
| `flutter_audio_manager` | Android, iOS | ❌ No | ❌ No | ❌ Inactive |
| `sound_mode` | Android only | ❌ No | ❌ No | ❌ Inactive |
| `volume_controller` | All | ❌ No | ❌ No | ✅ Active |

---

## Demo

See real-time audio route switching (speaker ↔ earpiece ↔ Bluetooth ↔ wired headset) in action:

### Android

<p align="center">
  <img src="https://github.com/novaquaker866/voip_audio_route_manager/blob/imp/doc-update/doc/Images/voip_audio_route_manager_android_example.gif?raw=true" alt="Android VoIP audio route switching demo - transitions between speakerphone, earpiece, Bluetooth headset, and wired headphones in real time" width="300">
  <br>
  <em>Android: Real-time detection and switching across all connected audio output devices.</em>
</p>

### Web

<p align="center">
  <img src="https://github.com/novaquaker866/voip_audio_route_manager/blob/imp/doc-update/doc/Images/voip_audio_route_manager_web_example.gif?raw=true" alt="Web browser audio output device selection demo - listing and switching between speaker, Bluetooth, and headset via MediaDevices API" width="600">
  <br>
  <em>Web: Device labels populate after media permission grant; route changes reflect immediately.</em>
</p>

---

## Contributing & Local Development

We welcome contributions! This project is structured as a **Federated Flutter Plugin** with separate packages for each platform.

### Repository Structure

```
voip_audio_route_manager/                    # Client app-facing package
├── voip_audio_route_manager_platform_interface/  # Contract definition
├── voip_audio_route_manager_android/        # Android implementation
├── voip_audio_route_manager_ios/            # iOS implementation
├── voip_audio_route_manager_macos/          # macOS implementation
└── voip_audio_route_manager_web/            # Web implementation
```

### Getting Started

1. Fork the repository
2. Install [FVM](https://fvm.app/) and run `fvm install`
3. Run `melos bootstrap` to link all packages
4. Make your changes and add tests
5. Ensure all CI checks pass: `melos run analyze && melos run test`
6. Submit a [Pull Request](https://github.com/your-org/voip_audio_route_manager/pulls)

> 📘 Read the full [Contributing Guide](https://github.com/your-org/voip_audio_route_manager/blob/main/CONTRIBUTING.md) for details.

---

## Changelog

See the [CHANGELOG.md](https://github.com/your-org/voip_audio_route_manager/blob/main/CHANGELOG.md) for a complete history of releases and breaking changes.

### Recent Highlights

- **v1.1.0** — Added macOS support, improved Bluetooth detection on Android 14+, Web MediaDevices fallback.
- **v1.0.0** — Stable release with Android, iOS, and Web support.
- **v0.9.0** — Beta release with federated plugin architecture.

---

## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).

```
MIT License

Copyright (c) 2024 [Your Name or Organization]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

<p align="center">
  Made with ❤️ for the Flutter community.
  <br>
  <a href="https://pub.dev/packages/voip_audio_route_manager">pub.dev</a> •
  <a href="https://github.com/your-org/voip_audio_route_manager">GitHub</a> •
  <a href="https://github.com/your-org/voip_audio_route_manager/issues">Issues</a>
</p>
