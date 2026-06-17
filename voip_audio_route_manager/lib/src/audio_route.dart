enum AudioRouteType {
  speaker,
  earpiece,
  bluetooth,
  wiredHeadset,
  none,
  unknown
}

class AudioRoute {
  final AudioRouteType type;
  final String? name;
  final int? id;

  const AudioRoute({required this.type, this.name, this.id});

  factory AudioRoute.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String? ?? 'unknown';
    return AudioRoute(
      type: _parseType(typeStr),
      name: map['name'] as String?,
      id: map['id'] as int?,
    );
  }

  static AudioRouteType _parseType(String raw) => switch (raw) {
        'speaker' => AudioRouteType.speaker,
        'earpiece' => AudioRouteType.earpiece,
        'bluetooth' => AudioRouteType.bluetooth,
        'wired_headset' => AudioRouteType.wiredHeadset,
        'none' => AudioRouteType.none,
        _ => AudioRouteType.unknown,
      };

  bool get isSpeaker => type == AudioRouteType.speaker;
  bool get isEarpiece => type == AudioRouteType.earpiece;
  bool get isBluetooth => type == AudioRouteType.bluetooth;
  bool get isWiredHeadset => type == AudioRouteType.wiredHeadset;

  @override
  String toString() => 'AudioRoute(type: $type, name: $name)';
}
