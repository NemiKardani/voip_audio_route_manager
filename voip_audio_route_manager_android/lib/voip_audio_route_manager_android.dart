import 'package:voip_audio_route_manager_platform_interface/voip_audio_route_manager_platform_interface.dart';

/// Android implementation of [VoipAudioRouteManagerPlatform].
class FlutterVoipAudioRouteManagerAndroid extends MethodChannelVoipAudioRouteManager {
  /// Registers this class as the default instance of [VoipAudioRouteManagerPlatform].
  static void registerWith() {
    VoipAudioRouteManagerPlatform.instance = FlutterVoipAudioRouteManagerAndroid();
  }
}
