import 'dart:async';
import 'package:flutter/services.dart';
import 'audio_device_model.dart';
import 'platform_interface.dart';

/// An implementation of [VoipAudioRouteManagerPlatform] that uses method channels.
class MethodChannelVoipAudioRouteManager extends VoipAudioRouteManagerPlatform {
  final MethodChannel _methodChannel = const MethodChannel('voip_audio_route_manager');
  final EventChannel _eventChannel = const EventChannel('voip_audio_route_manager/events');

  Stream<Map<dynamic, dynamic>>? _rawEventStream;

  Stream<Map<dynamic, dynamic>> get _eventStream {
    _rawEventStream ??= _eventChannel
        .receiveBroadcastStream()
        .cast<Map<dynamic, dynamic>>();
    return _rawEventStream!;
  }

  @override
  Future<void> initialize({bool enableLogs = false}) async {
    await _methodChannel.invokeMethod('initialize', {
      'enableLogs': enableLogs,
    });
  }

  @override
  Future<List<AudioOutputDevice>> availableDevices() async {
    final result = await _methodChannel.invokeMethod<List<dynamic>>('availableDevices');
    if (result == null) return [];
    return result
        .map((e) => AudioOutputDevice.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  @override
  Future<AudioOutputDevice?> currentAudioRoute() async {
    final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('currentAudioRoute');
    if (result == null) return null;
    return AudioOutputDevice.fromMap(result);
  }

  @override
  Future<void> setAudioRoute(String id) async {
    await _methodChannel.invokeMethod('setAudioRoute', {'id': id});
  }

  @override
  Future<void> setAudioRouteType(String type) async {
    await _methodChannel.invokeMethod('setAudioRouteType', {'type': type});
  }

  @override
  Future<void> setAudioRouteByName(String name) async {
    await _methodChannel.invokeMethod('setAudioRouteByName', {'name': name});
  }

  @override
  Stream<List<AudioOutputDevice>> get audioDevicesStream {
    return _eventStream
        .where((event) => event['event'] == 'devices_changed')
        .map((event) {
          final list = event['devices'] as List<dynamic>? ?? [];
          return list
              .map((e) => AudioOutputDevice.fromMap(e as Map<dynamic, dynamic>))
              .toList();
        });
  }

  @override
  Stream<AudioOutputDevice> get onDeviceConnected {
    return _eventStream
        .where((event) => event['event'] == 'device_connected')
        .map((event) => AudioOutputDevice.fromMap(event['device'] as Map<dynamic, dynamic>));
  }

  @override
  Stream<AudioOutputDevice> get onDeviceDisconnected {
    return _eventStream
        .where((event) => event['event'] == 'device_disconnected')
        .map((event) => AudioOutputDevice.fromMap(event['device'] as Map<dynamic, dynamic>));
  }

  @override
  Stream<AudioOutputDevice> get onRouteChanged {
    return _eventStream
        .where((event) => event['event'] == 'route_changed')
        .map((event) => AudioOutputDevice.fromMap(event['device'] as Map<dynamic, dynamic>));
  }

  @override
  Stream<bool> get onAudioFocusChanged {
    return _eventStream
        .where((event) => event['event'] == 'audio_focus_changed')
        .map((event) => event['focused'] as bool? ?? false);
  }
}
