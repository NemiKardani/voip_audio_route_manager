import 'audio_device_model.dart';

/// High-level outcome of an audio route selection request.
enum AudioRouteStatus {
  /// The platform accepted the route request and the active route matches it.
  success,

  /// The route request was accepted, but the platform has not yet reported it
  /// as the active route.
  pending,

  /// The requested device, type, or name could not be found.
  notFound,

  /// The platform rejected the request even though the target was available.
  rejected,

  /// The operation is not supported on this platform or browser.
  unsupported,

  /// The operation needs a permission the app does not currently have.
  permissionDenied,

  /// The active route was cleared or returned to the platform default.
  cleared,

  /// The platform reported an error that does not fit a more specific status.
  error,
}

/// Result details for a route selection or clearing request.
class AudioRouteResult {
  /// Creates a route result.
  const AudioRouteResult({
    required this.success,
    required this.status,
    this.requestedDevice,
    this.actualDevice,
    this.message,
    this.errorCode,
  });

  /// Whether the request achieved the desired state.
  final bool success;

  /// Machine-readable status for the request.
  final AudioRouteStatus status;

  /// The device the caller asked to use, when known.
  final AudioOutputDevice? requestedDevice;

  /// The device the platform reports as active after the request.
  final AudioOutputDevice? actualDevice;

  /// Human-readable diagnostic context from the platform.
  final String? message;

  /// Platform-specific error code, when available.
  final String? errorCode;

  /// Converts a platform map into an [AudioRouteResult].
  factory AudioRouteResult.fromMap(Map<dynamic, dynamic> map) {
    final statusName = (map['status'] ?? '').toString();
    final status = AudioRouteStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => map['success'] == true
          ? AudioRouteStatus.success
          : AudioRouteStatus.error,
    );

    final requestedMap = map['requestedDevice'];
    final actualMap = map['actualDevice'];

    return AudioRouteResult(
      success: map['success'] == true,
      status: status,
      requestedDevice:
          requestedMap is Map ? AudioOutputDevice.fromMap(requestedMap) : null,
      actualDevice:
          actualMap is Map ? AudioOutputDevice.fromMap(actualMap) : null,
      message: map['message']?.toString(),
      errorCode: map['errorCode']?.toString(),
    );
  }

  /// Converts this result to a platform map.
  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'status': status.name,
      if (requestedDevice != null) 'requestedDevice': requestedDevice!.toMap(),
      if (actualDevice != null) 'actualDevice': actualDevice!.toMap(),
      if (message != null) 'message': message,
      if (errorCode != null) 'errorCode': errorCode,
    };
  }

  @override
  String toString() {
    return 'AudioRouteResult(success: $success, status: ${status.name}, '
        'requestedDevice: $requestedDevice, actualDevice: $actualDevice, '
        'message: $message, errorCode: $errorCode)';
  }
}
