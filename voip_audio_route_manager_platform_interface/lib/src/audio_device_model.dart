/// Types of audio output devices supported.
enum AudioOutputType {
  /// Built-in speakerphone or device speaker.
  speaker,
  /// Built-in phone receiver (earpiece).
  receiver,
  /// Bluetooth audio output device (HFP, A2DP, or BLE).
  bluetooth,
  /// Wired headset or headphones plugged in via aux/jack.
  wiredHeadset,
  /// Apple AirPods specific bluetooth profile.
  airpods,
  /// USB external audio dock or interface.
  usbAudio,
  /// Connected vehicular CarPlay or Android Auto audio dock.
  carAudio,
  /// HDMI output screen or receiver.
  hdmi,
  /// Unsupported or unmapped audio output type.
  unknown,
}

/// Represents an audio output device with details about ID, name, type, and current selection status.
class AudioOutputDevice {
  /// The unique hardware identifier or logical ID of the audio output device.
  final String id;
  
  /// The human-readable display name of the audio output device.
  final String name;
  
  /// The mapped classification type of the audio output device.
  final AudioOutputType type;
  
  /// Indicates whether the audio routing engine is currently active on this device.
  final bool isSelected;

  /// Constructs an [AudioOutputDevice] instance.
  const AudioOutputDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.isSelected,
  });

  /// Creates a copy of this device with the given fields replaced.
  AudioOutputDevice copyWith({
    String? id,
    String? name,
    AudioOutputType? type,
    bool? isSelected,
  }) {
    return AudioOutputDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  /// Converts a map to an [AudioOutputDevice].
  factory AudioOutputDevice.fromMap(Map<dynamic, dynamic> map) {
    final typeStr = map['type'] as String?;
    final type = AudioOutputType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => AudioOutputType.unknown,
    );

    return AudioOutputDevice(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      type: type,
      isSelected: map['isSelected'] == true,
    );
  }

  /// Converts this device to a map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'isSelected': isSelected,
    };
  }

  @override
  String toString() {
    return 'AudioOutputDevice(id: $id, name: $name, type: ${type.name}, isSelected: $isSelected)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AudioOutputDevice &&
        other.id == id &&
        other.name == name &&
        other.type == type &&
        other.isSelected == isSelected;
  }

  @override
  int get hashCode {
    return Object.hash(id, name, type, isSelected);
  }
}
