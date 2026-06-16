import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';
import 'package:voip_audio_route_manager_platform_interface/voip_audio_route_manager_platform_interface.dart';

class MockVoipAudioRouteManagerPlatform extends VoipAudioRouteManagerPlatform
    with MockPlatformInterfaceMixin {
  final List<String> logCalls = [];
  bool initializeCalled = false;
  bool startCallSessionCalled = false;
  bool endCallSessionCalled = false;
  bool clearAudioRouteCalled = false;
  String? setRouteIdCalled;
  String? setRouteTypeCalled;
  String? setRouteNameCalled;
  String? selectRouteIdCalled;
  String? selectRouteTypeCalled;
  String? selectRouteNameCalled;

  @override
  Future<void> initialize({bool enableLogs = false}) async {
    initializeCalled = true;
  }

  @override
  Future<void> startCallSession() async {
    startCallSessionCalled = true;
  }

  @override
  Future<void> endCallSession() async {
    endCallSessionCalled = true;
  }

  @override
  Future<List<AudioOutputDevice>> availableDevices() async {
    return [
      const AudioOutputDevice(
        id: '1',
        name: 'Speaker',
        type: AudioOutputType.speaker,
        isSelected: true,
      ),
      const AudioOutputDevice(
        id: '2',
        name: 'Earpiece',
        type: AudioOutputType.receiver,
        isSelected: false,
      ),
    ];
  }

  @override
  Future<AudioOutputDevice?> currentAudioRoute() async {
    return const AudioOutputDevice(
      id: '1',
      name: 'Speaker',
      type: AudioOutputType.speaker,
      isSelected: true,
    );
  }

  @override
  Future<void> setAudioRoute(String id) async {
    setRouteIdCalled = id;
  }

  @override
  Future<void> setAudioRouteType(String type) async {
    setRouteTypeCalled = type;
  }

  @override
  Future<void> setAudioRouteByName(String name) async {
    setRouteNameCalled = name;
  }

  @override
  Future<AudioRouteResult> selectAudioRoute(String id) async {
    selectRouteIdCalled = id;
    return const AudioRouteResult(
      success: true,
      status: AudioRouteStatus.success,
      actualDevice: AudioOutputDevice(
        id: '1',
        name: 'Speaker',
        type: AudioOutputType.speaker,
        isSelected: true,
      ),
    );
  }

  @override
  Future<AudioRouteResult> selectAudioRouteType(String type) async {
    selectRouteTypeCalled = type;
    return const AudioRouteResult(
      success: true,
      status: AudioRouteStatus.success,
    );
  }

  @override
  Future<AudioRouteResult> selectAudioRouteByName(String name) async {
    selectRouteNameCalled = name;
    return const AudioRouteResult(
      success: true,
      status: AudioRouteStatus.success,
    );
  }

  @override
  Future<AudioRouteResult> clearAudioRoute() async {
    clearAudioRouteCalled = true;
    return const AudioRouteResult(
      success: true,
      status: AudioRouteStatus.cleared,
    );
  }
}

void main() {
  group('VoipAudioRouteManager tests', () {
    late MockVoipAudioRouteManagerPlatform mockPlatform;

    setUp(() {
      mockPlatform = MockVoipAudioRouteManagerPlatform();
      VoipAudioRouteManagerPlatform.instance = mockPlatform;
    });

    test('initialize delegates correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      await manager.initialize(enableLogs: true);
      expect(mockPlatform.initializeCalled, true);
    });

    test('call session lifecycle delegates correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      await manager.startCallSession();
      await manager.endCallSession();
      expect(mockPlatform.startCallSessionCalled, true);
      expect(mockPlatform.endCallSessionCalled, true);
    });

    test('availableDevices delegates correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      final devices = await manager.availableDevices();
      expect(devices.length, 2);
      expect(devices.first.name, 'Speaker');
    });

    test('currentAudioRoute delegates correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      final current = await manager.currentAudioRoute();
      expect(current?.id, '1');
      expect(current?.isSelected, true);
    });

    test('setAudioRoute delegates ID correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      const device = AudioOutputDevice(
        id: '123',
        name: 'Bluetooth',
        type: AudioOutputType.bluetooth,
        isSelected: false,
      );
      await manager.setAudioRoute(device);
      expect(mockPlatform.setRouteIdCalled, '123');
    });

    test('setAudioRouteById delegates ID correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      await manager.setAudioRouteById('abc');
      expect(mockPlatform.setRouteIdCalled, 'abc');
    });

    test('setAudioRouteType delegates type correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      await manager.setAudioRouteType(AudioOutputType.airpods);
      expect(mockPlatform.setRouteTypeCalled, 'airpods');
    });

    test('setAudioRouteByName delegates name correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      await manager.setAudioRouteByName('AirPods');
      expect(mockPlatform.setRouteNameCalled, 'AirPods');
    });

    test('selectAudioRoute delegates ID and returns result', () async {
      final manager = VoipAudioRouteManager.instance;
      const device = AudioOutputDevice(
        id: '123',
        name: 'Bluetooth',
        type: AudioOutputType.bluetooth,
        isSelected: false,
      );
      final result = await manager.selectAudioRoute(device);
      expect(mockPlatform.selectRouteIdCalled, '123');
      expect(result.success, true);
      expect(result.status, AudioRouteStatus.success);
    });

    test('selectAudioRouteById delegates ID correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      await manager.selectAudioRouteById('abc');
      expect(mockPlatform.selectRouteIdCalled, 'abc');
    });

    test('selectAudioRouteType delegates type correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      await manager.selectAudioRouteType(AudioOutputType.speaker);
      expect(mockPlatform.selectRouteTypeCalled, 'speaker');
    });

    test('selectAudioRouteByName delegates name correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      await manager.selectAudioRouteByName('AirPods');
      expect(mockPlatform.selectRouteNameCalled, 'AirPods');
    });

    test('clearAudioRoute delegates correctly', () async {
      final manager = VoipAudioRouteManager.instance;
      final result = await manager.clearAudioRoute();
      expect(mockPlatform.clearAudioRouteCalled, true);
      expect(result.status, AudioRouteStatus.cleared);
    });
  });
}
