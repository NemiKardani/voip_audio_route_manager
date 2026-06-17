import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'audio_device_model.dart';
import 'audio_route_result.dart';
import 'method_channel_implementation.dart';

/// The common platform interface contract for the [VoipAudioRouteManager] plugin.
abstract class VoipAudioRouteManagerPlatform extends PlatformInterface {
  /// Constructs a VoipAudioRouteManagerPlatform.
  VoipAudioRouteManagerPlatform() : super(token: _token);

  static final Object _token = Object();

  static VoipAudioRouteManagerPlatform _instance =
      MethodChannelVoipAudioRouteManager();

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

  /// Activates platform audio state for an active VoIP call.
  ///
  /// Native implementations should request/activate the platform's voice
  /// communication audio mode here, without selecting a specific output route.
  Future<void> startCallSession() {
    return Future.value();
  }

  /// Ends the active VoIP audio session and releases any route/focus requests.
  Future<void> endCallSession() {
    return Future.value();
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

  /// Sets the active route by ID and returns the requested and actual route.
  Future<AudioRouteResult> selectAudioRoute(String id) async {
    final devices = await availableDevices();
    final requested = devices.cast<AudioOutputDevice?>().firstWhere(
          (device) => device?.id == id,
          orElse: () => null,
        );

    if (requested == null) {
      return const AudioRouteResult(
        success: false,
        status: AudioRouteStatus.notFound,
        message: 'No audio output device matched the requested ID.',
      );
    }

    try {
      await setAudioRoute(id);
      final actual = await currentAudioRoute();
      final matches = actual?.id == id || actual?.type == requested.type;
      return AudioRouteResult(
        success: matches,
        status: matches ? AudioRouteStatus.success : AudioRouteStatus.pending,
        requestedDevice: requested,
        actualDevice: actual,
        message: matches
            ? 'Audio route changed successfully.'
            : 'Route request was sent, but the active route does not match yet.',
      );
    } catch (error) {
      return AudioRouteResult(
        success: false,
        status: AudioRouteStatus.error,
        requestedDevice: requested,
        actualDevice: await currentAudioRoute(),
        message: error.toString(),
      );
    }
  }

  /// Sets the active route by type and returns the requested and actual route.
  Future<AudioRouteResult> selectAudioRouteType(String type) async {
    final devices = await availableDevices();
    final requested = devices.cast<AudioOutputDevice?>().firstWhere(
          (device) => device?.type.name == type,
          orElse: () => null,
        );

    if (requested == null) {
      return AudioRouteResult(
        success: false,
        status: AudioRouteStatus.notFound,
        message: 'No audio output device matched type $type.',
      );
    }

    return selectAudioRoute(requested.id);
  }

  /// Sets the active route by matching a device name.
  Future<AudioRouteResult> selectAudioRouteByName(String name) async {
    final devices = await availableDevices();
    final requested = devices.cast<AudioOutputDevice?>().firstWhere(
          (device) =>
              device?.name.toLowerCase().contains(name.toLowerCase()) == true,
          orElse: () => null,
        );

    if (requested == null) {
      return AudioRouteResult(
        success: false,
        status: AudioRouteStatus.notFound,
        message: 'No audio output device matched name $name.',
      );
    }

    return selectAudioRoute(requested.id);
  }

  /// Clears a previously requested route and returns to platform default routing.
  Future<void> clearAudioRoute() async {}

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

  /// Returns the list of currently available audio output routes.
  Future<List<dynamic>> getAvailableRoutes() {
    throw UnimplementedError('getAvailableRoutes() has not been implemented.');
  }

  /// Switches the audio output to speaker.
  Future<bool> switchToSpeaker() {
    throw UnimplementedError('switchToSpeaker() has not been implemented.');
  }

  /// Switches the audio output to earpiece.
  Future<bool> switchToEarpiece() {
    throw UnimplementedError('switchToEarpiece() has not been implemented.');
  }

  /// Stream that emits the current route name whenever it changes.
  Stream<String> get onRouteChangedStream {
    throw UnimplementedError('onRouteChangedStream has not been implemented.');
  }
}
