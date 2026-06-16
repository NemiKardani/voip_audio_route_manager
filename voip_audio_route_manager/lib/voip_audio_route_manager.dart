import 'dart:async';
import 'package:voip_audio_route_manager_platform_interface/voip_audio_route_manager_platform_interface.dart';
import 'src/logger.dart';

export 'package:voip_audio_route_manager_platform_interface/voip_audio_route_manager_platform_interface.dart'
    show AudioOutputDevice, AudioOutputType, AudioRouteResult, AudioRouteStatus;

/// Advanced audio output routing manager for VoIP applications.
class VoipAudioRouteManager {
  VoipAudioRouteManager._();

  /// Shared instance of the audio route manager.
  static final VoipAudioRouteManager instance = VoipAudioRouteManager._();

  /// Initialises the route manager, optionally enabling console logging.
  Future<void> initialize({bool enableLogs = false}) async {
    VoipAudioLogger.enableLogs = enableLogs;
    VoipAudioLogger.log('Initializing VoipAudioRouteManager...');
    try {
      await VoipAudioRouteManagerPlatform.instance
          .initialize(enableLogs: enableLogs);
      VoipAudioLogger.log('Initialization completed.');
    } catch (e) {
      VoipAudioLogger.log('Initialization failed: $e');
      rethrow;
    }
  }

  /// Activates platform audio state for a live VoIP call.
  Future<void> startCallSession() async {
    VoipAudioLogger.log('Starting VoIP call audio session...');
    await VoipAudioRouteManagerPlatform.instance.startCallSession();
  }

  /// Ends the VoIP call audio session and releases focus/route requests.
  Future<void> endCallSession() async {
    VoipAudioLogger.log('Ending VoIP call audio session...');
    await VoipAudioRouteManagerPlatform.instance.endCallSession();
  }

  /// Returns the list of currently available audio output devices.
  Future<List<AudioOutputDevice>> availableDevices() async {
    VoipAudioLogger.log('Requesting available devices...');
    final devices =
        await VoipAudioRouteManagerPlatform.instance.availableDevices();
    VoipAudioLogger.log('Available devices: $devices');
    return devices;
  }

  /// Returns the currently active audio output route.
  Future<AudioOutputDevice?> currentAudioRoute() async {
    VoipAudioLogger.log('Requesting current audio route...');
    final route =
        await VoipAudioRouteManagerPlatform.instance.currentAudioRoute();
    VoipAudioLogger.log('Current audio route: $route');
    return route;
  }

  /// Sets the active audio output route using the [AudioOutputDevice] object.
  Future<void> setAudioRoute(AudioOutputDevice device) async {
    VoipAudioLogger.log('Setting audio route to device: $device');
    await VoipAudioRouteManagerPlatform.instance.setAudioRoute(device.id);
  }

  /// Sets the active audio output route using its unique [id].
  Future<void> setAudioRouteById(String id) async {
    VoipAudioLogger.log('Setting audio route by ID: $id');
    await VoipAudioRouteManagerPlatform.instance.setAudioRoute(id);
  }

  /// Sets the active audio output route using its [type].
  Future<void> setAudioRouteType(AudioOutputType type) async {
    VoipAudioLogger.log('Setting audio route type: ${type.name}');
    await VoipAudioRouteManagerPlatform.instance.setAudioRouteType(type.name);
  }

  /// Sets the active audio output route by matching its device [name].
  Future<void> setAudioRouteByName(String name) async {
    VoipAudioLogger.log('Setting audio route by name: $name');
    await VoipAudioRouteManagerPlatform.instance.setAudioRouteByName(name);
  }

  /// Sets the active audio output route and returns the platform result.
  Future<AudioRouteResult> selectAudioRoute(AudioOutputDevice device) async {
    VoipAudioLogger.log('Selecting audio route with result: $device');
    final result = await VoipAudioRouteManagerPlatform.instance
        .selectAudioRoute(device.id);
    VoipAudioLogger.log('Audio route selection result: $result');
    return result;
  }

  /// Sets the active audio output route by ID and returns the platform result.
  Future<AudioRouteResult> selectAudioRouteById(String id) async {
    VoipAudioLogger.log('Selecting audio route by ID with result: $id');
    final result =
        await VoipAudioRouteManagerPlatform.instance.selectAudioRoute(id);
    VoipAudioLogger.log('Audio route selection result: $result');
    return result;
  }

  /// Sets the active audio output route by type and returns the platform result.
  Future<AudioRouteResult> selectAudioRouteType(AudioOutputType type) async {
    VoipAudioLogger.log('Selecting audio route type with result: ${type.name}');
    final result = await VoipAudioRouteManagerPlatform.instance
        .selectAudioRouteType(type.name);
    VoipAudioLogger.log('Audio route selection result: $result');
    return result;
  }

  /// Sets the active audio output route by name and returns the platform result.
  Future<AudioRouteResult> selectAudioRouteByName(String name) async {
    VoipAudioLogger.log('Selecting audio route by name with result: $name');
    final result = await VoipAudioRouteManagerPlatform.instance
        .selectAudioRouteByName(name);
    VoipAudioLogger.log('Audio route selection result: $result');
    return result;
  }

  /// Clears any explicit route request and returns to platform default routing.
  Future<AudioRouteResult> clearAudioRoute() async {
    VoipAudioLogger.log('Clearing requested audio route...');
    final result =
        await VoipAudioRouteManagerPlatform.instance.clearAudioRoute();
    VoipAudioLogger.log('Clear audio route result: $result');
    return result;
  }

  /// Emits updates containing the full list of available devices (including selection status).
  Stream<List<AudioOutputDevice>> get audioDevicesStream {
    return VoipAudioRouteManagerPlatform.instance.audioDevicesStream
        .map((devices) {
      VoipAudioLogger.log('Audio Devices Stream Update: $devices');
      return devices;
    });
  }

  /// Stream of individual devices that just connected.
  Stream<AudioOutputDevice> get onDeviceConnected {
    return VoipAudioRouteManagerPlatform.instance.onDeviceConnected
        .map((device) {
      if (device.type == AudioOutputType.bluetooth ||
          device.type == AudioOutputType.airpods) {
        VoipAudioLogger.log('Bluetooth Connected: ${device.name}');
      } else if (device.type == AudioOutputType.wiredHeadset) {
        VoipAudioLogger.log('Wired Headset Connected: ${device.name}');
      } else {
        VoipAudioLogger.log(
            'Device Connected: ${device.name} (${device.type.name})');
      }
      return device;
    });
  }

  /// Stream of individual devices that just disconnected.
  Stream<AudioOutputDevice> get onDeviceDisconnected {
    return VoipAudioRouteManagerPlatform.instance.onDeviceDisconnected
        .map((device) {
      if (device.type == AudioOutputType.bluetooth ||
          device.type == AudioOutputType.airpods) {
        VoipAudioLogger.log('Bluetooth Disconnected: ${device.name}');
      } else if (device.type == AudioOutputType.wiredHeadset) {
        VoipAudioLogger.log('Wired Headset Disconnected: ${device.name}');
      } else {
        VoipAudioLogger.log(
            'Device Disconnected: ${device.name} (${device.type.name})');
      }
      return device;
    });
  }

  /// Stream of the newly selected active audio output route.
  Stream<AudioOutputDevice> get onRouteChanged {
    return VoipAudioRouteManagerPlatform.instance.onRouteChanged.map((device) {
      if (device.type == AudioOutputType.speaker) {
        VoipAudioLogger.log('Speaker Enabled');
      } else if (device.type == AudioOutputType.receiver) {
        VoipAudioLogger.log('Receiver Enabled');
      } else {
        VoipAudioLogger.log(
            'Route Changed: ${device.name} (${device.type.name})');
      }
      return device;
    });
  }

  /// Stream of audio focus changes (gained or lost).
  Stream<bool> get onAudioFocusChanged {
    return VoipAudioRouteManagerPlatform.instance.onAudioFocusChanged
        .map((focused) {
      VoipAudioLogger.log(
          'Audio Focus Changed: ${focused ? "Gained" : "Lost"}');
      return focused;
    });
  }

  /// Requests audio/microphone permissions from the platform.
  ///
  /// This is particularly important on Web, where browser security hides actual
  /// audio output devices and their names/labels until permission is granted.
  Future<bool> requestPermissions() {
    return VoipAudioRouteManagerPlatform.instance.requestPermissions();
  }

  /// Prompts the user to select an audio output device.
  ///
  /// Particularly useful on Web to trigger the native browser output selection dialog
  /// according to the W3C Audio Output Devices API specification. An optional [deviceId]
  /// can be passed to suggest a preferred device to select initially.
  Future<AudioOutputDevice?> selectAudioOutput({String? deviceId}) {
    return VoipAudioRouteManagerPlatform.instance
        .selectAudioOutput(deviceId: deviceId);
  }
}
