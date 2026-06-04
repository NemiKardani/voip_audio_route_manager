import 'package:flutter_test/flutter_test.dart';
import 'package:voip_audio_route_manager_platform_interface/voip_audio_route_manager_platform_interface.dart';

void main() {
  group('AudioOutputDevice tests', () {
    test('serialization and deserialization from map works', () {
      const device = AudioOutputDevice(
        id: 'dev_123',
        name: 'My Bluetooth Headset',
        type: AudioOutputType.bluetooth,
        isSelected: true,
      );

      final map = device.toMap();
      expect(map['id'], 'dev_123');
      expect(map['name'], 'My Bluetooth Headset');
      expect(map['type'], 'bluetooth');
      expect(map['isSelected'], true);

      final decoded = AudioOutputDevice.fromMap(map);
      expect(decoded.id, device.id);
      expect(decoded.name, device.name);
      expect(decoded.type, device.type);
      expect(decoded.isSelected, device.isSelected);
    });

    test('invalid type string fallback to unknown', () {
      final map = {
        'id': 'dev_xyz',
        'name': 'Weird Audio Source',
        'type': 'non_existent_type',
        'isSelected': false,
      };

      final decoded = AudioOutputDevice.fromMap(map);
      expect(decoded.type, AudioOutputType.unknown);
    });

    test('equality checks are correct', () {
      const dev1 = AudioOutputDevice(
        id: '1',
        name: 'Speaker',
        type: AudioOutputType.speaker,
        isSelected: false,
      );
      const dev2 = AudioOutputDevice(
        id: '1',
        name: 'Speaker',
        type: AudioOutputType.speaker,
        isSelected: false,
      );
      const dev3 = AudioOutputDevice(
        id: '2',
        name: 'Speaker',
        type: AudioOutputType.speaker,
        isSelected: false,
      );

      expect(dev1, dev2);
      expect(dev1.hashCode, dev2.hashCode);
      expect(dev1, isNot(dev3));
    });
  });
}
