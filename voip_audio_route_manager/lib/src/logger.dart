import 'package:flutter/foundation.dart';

class VoipAudioLogger {
  static bool enableLogs = false;

  static void log(String message) {
    if (enableLogs && kDebugMode) {
      // ignore: avoid_print
      print('[VoipAudio] $message');
    }
  }
}
