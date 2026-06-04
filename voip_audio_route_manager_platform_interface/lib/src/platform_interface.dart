import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'audio_device_model.dart';
import 'method_channel_implementation.dart';

/// The common platform interface contract for the [VoipAudioRouteManager] plugin.
abstract class VoipAudioRouteManagerPlatform extends PlatformInterface {
  /// Constructs a VoipAudioRouteManagerPlatform.
  VoipAudioRouteManagerPlatform() : super(token: _token);

  static final Object _token = Object();

  static VoipAudioRouteManagerPlatform _instance = MethodChannelVoipAudioRouteManager();

  /// The default instance of [VoipAudioRouteManagerPlatform] to use.
  ///
  /// Defaults to [MethodChannelVoipAudioRouteManager].
  static VoipAudioRouteManagerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [VoipAudioRouteManagerPlatform] when
  /// they register themselves.
  static set instance(VoipAudioRouteManagerPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Initialises the audio route manager, optionally enabling logs.
  Future<void> initialize({bool enableLogs = false}) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Returns the list of currently available audio output devices.
  Future<List<AudioOutputDevice>> availableDevices() {
    throw UnimplementedError('availableDevices() has not been implemented.');
  }

  /// Returns the currently active audio output route.
  Future<AudioOutputDevice?> currentAudioRoute() {
    throw UnimplementedError('currentAudioRoute() has not been implemented.');
  }

  /// Sets the active audio output route using its unique identifier.
  Future<void> setAudioRoute(String id) {
    throw UnimplementedError('setAudioRoute() has not been implemented.');
  }

  /// Sets the active audio output route using its type (name of enum).
  Future<void> setAudioRouteType(String type) {
    throw UnimplementedError('setAudioRouteType() has not been implemented.');
  }

  /// Sets the active audio output route by matching its device name.
  Future<void> setAudioRouteByName(String name) {
    throw UnimplementedError('setAudioRouteByName() has not been implemented.');
  }

  /// Emits updates containing the full list of available devices (including selection status).
  Stream<List<AudioOutputDevice>> get audioDevicesStream {
    throw UnimplementedError('audioDevicesStream has not been implemented.');
  }

  /// Stream of individual devices that just connected.
  Stream<AudioOutputDevice> get onDeviceConnected {
    throw UnimplementedError('onDeviceConnected has not been implemented.');
  }

  /// Stream of individual devices that just disconnected.
  Stream<AudioOutputDevice> get onDeviceDisconnected {
    throw UnimplementedError('onDeviceDisconnected has not been implemented.');
  }

  /// Stream of the newly selected active audio output route.
  Stream<AudioOutputDevice> get onRouteChanged {
    throw UnimplementedError('onRouteChanged has not been implemented.');
  }

  /// Stream of audio focus changes (gained or lost).
  Stream<bool> get onAudioFocusChanged {
    throw UnimplementedError('onAudioFocusChanged has not been implemented.');
  }

  /// Requests audio/microphone permissions from the platform.
  ///
  /// On the Web, this prompts for microphone permission so that browser
  /// security allows enumerating all output devices with correct labels and IDs.
  /// On other platforms, this resolves to true (permissions should be handled
  /// using platform-specific permission libraries).
  Future<bool> requestPermissions() {
    return Future.value(true);
  }

  /// Prompts the user to select an audio output device.
  ///
  /// On the Web, this invokes the browser's native Audio Output Devices API prompt
  /// (`navigator.mediaDevices.selectAudioOutput()`), allowing users to grant permission
  /// and select a device in one action. An optional [deviceId] can be passed to suggest
  /// a preferred device to select initially.
  /// On other platforms, this resolves to null.
  Future<AudioOutputDevice?> selectAudioOutput({String? deviceId}) {
    return Future.value(null);
  }
}
