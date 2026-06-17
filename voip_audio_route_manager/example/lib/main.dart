import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:voip_audio_route_manager/voip_audio_route_manager.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoIP Audio Route Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
        colorScheme: const ColorScheme.dark().copyWith(
          primary: const Color(0xFF6366F1), // Indigo 500
          secondary: const Color(0xFF10B981), // Emerald 500
          surface: const Color(0xFF1E293B), // Slate 800
          error: const Color(0xFFEF4444), // Rose 500
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E293B),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _manager = VoipAudioRouteManager.instance;
  List<AudioOutputDevice> _devices = [];
  AudioOutputDevice? _currentRoute;

  bool _initialized = false;
  bool _audioFocus = false;
  bool _isCallActive = false;

  final List<String> _consoleLogs = [];
  final _logScrollController = ScrollController();
  final List<StreamSubscription> _subscriptions = [];
  Timer? _scrollTimer;

  @override
  void initState() {
    super.initState();
    _addLog('App started. Tap "Initialize Manager" to begin.');
  }

  /// Initialises the VoipAudioRouteManager and registers listeners to handle updates.
  Future<void> _initializeManager() async {
    try {
      // Step 1: Initialise the manager. Enabling logs routes internal console outputs.
      await _manager.initialize(enableLogs: true);
      _addLog('VoipAudioRouteManager initialised successfully.');

      // Step 2: Listen to streams for changes in the audio environment.
      _subscriptions.addAll([
        // Emitted when the full list of available hardware devices updates.
        _manager.audioDevicesStream.listen((devices) {
          setState(() {
            _devices = devices;
          });
          _addLog(
              'Devices Stream: Received ${devices.length} available devices.');
        }),
        // Emitted when the active audio output route changes (e.g. bluetooth connected/selected).
        _manager.onRouteChanged.listen((route) {
          setState(() {
            _currentRoute = _devices.firstWhere(
              (d) =>
                  d.type.name == route ||
                  d.id == route ||
                  d.name.toLowerCase().contains(route.toLowerCase()),
              orElse: () => AudioOutputDevice(
                id: route,
                name: route.toUpperCase(),
                type: AudioOutputType.values.firstWhere(
                  (t) => t.name == route,
                  orElse: () => AudioOutputType.unknown,
                ),
                isSelected: true,
              ),
            );
          });
          _addLog('Route Changed Stream: $route');
        }),
        // Emitted when a physical device connects.
        _manager.onDeviceConnected.listen((device) {
          _addLog('Device Connected: ${device.name} [${device.type.name}]');
        }),
        // Emitted when a physical device disconnects.
        _manager.onDeviceDisconnected.listen((device) {
          _addLog('Device Disconnected: ${device.name} [${device.type.name}]');
        }),
        // Emitted when the app's audio focus is granted or lost on the system.
        _manager.onAudioFocusChanged.listen((focused) {
          setState(() {
            _audioFocus = focused;
          });
          _addLog('Audio Focus Stream: ${focused ? "Gained" : "Lost"}');
        }),
      ]);

      // Step 3: Fetch initial platform states.
      final current = await _manager.currentAudioRoute();
      final available = await _manager.availableDevices();

      setState(() {
        _currentRoute = current;
        _devices = available;
        _initialized = true;
      });

      _addLog('Initial route: ${_currentRoute?.name ?? "None"}');
      _addLog('Initial devices loaded: ${available.length} found.');
    } catch (e) {
      _addLog('Initialization error: $e');
    }
  }

  /// Refreshes the local widget state by fetching the current route and device list directly.
  Future<void> _refreshRoute() async {
    try {
      final current = await _manager.currentAudioRoute();
      final available = await _manager.availableDevices();
      setState(() {
        _currentRoute = current;
        _devices = available;
      });
    } catch (e) {
      _addLog('Refresh state error: $e');
    }
  }

  /// Starts a VoIP call audio session.
  ///
  /// This requests system audio focus and configures the platform's audio mode
  /// (e.g., MODE_IN_COMMUNICATION on Android, Voip/PlayAndRecord on iOS) for high-quality
  /// hardware AEC (Acoustic Echo Cancellation) and appropriate routing.
  Future<void> _startCallSession() async {
    try {
      _addLog(
          'Starting VoIP call session (requesting focus & communication mode)...');
      await _manager.startCallSession();
      setState(() {
        _isCallActive = true;
      });
      _addLog('VoIP call session active.');
    } catch (e) {
      _addLog('Error starting call session: $e');
    }
  }

  /// Ends the VoIP call audio session.
  ///
  /// This releases the system audio focus and reverts the communication mode back to
  /// normal, allowing other apps to request audio focus.
  Future<void> _endCallSession() async {
    try {
      _addLog(
          'Ending VoIP call session (releasing focus & communication mode)...');
      await _manager.endCallSession();
      setState(() {
        _isCallActive = false;
      });
      _addLog('VoIP call session ended.');
    } catch (e) {
      _addLog('Error ending call session: $e');
    }
  }

  /// Switches the audio output to a target device using the selectAudioRoute API.
  /// This API returns a rich AudioRouteResult indicating success/failure details.
  Future<void> _selectDeviceRoute(AudioOutputDevice device) async {
    try {
      _addLog('Requesting route change to: ${device.name}...');
      final result = await _manager.selectAudioRoute(device);
      _processRouteResult(result);
    } catch (e) {
      _addLog('Route selection error: $e');
    }
  }

  /// Switches the audio output to a target type using the selectAudioRouteType API.
  Future<void> _selectDeviceRouteType(AudioOutputType type) async {
    try {
      _addLog('Requesting route change to type: ${type.name}...');
      final result = await _manager.selectAudioRouteType(type);
      _processRouteResult(result);
    } catch (e) {
      _addLog('Route type selection error: $e');
    }
  }

  /// Clears any explicitly set audio route overrides and returns to default routing.
  Future<void> _clearExplicitRoute() async {
    try {
      _addLog('Clearing explicit audio route override...');
      await _manager.clearAudioRoute();
      _addLog('Explicit audio route override cleared.');
      _refreshRoute();
    } catch (e) {
      _addLog('Error clearing audio route: $e');
    }
  }

  /// Helper to display and log the detailed output of an AudioRouteResult.
  void _processRouteResult(AudioRouteResult result) {
    _addLog('Result: success=${result.success}, status=${result.status.name}, '
        'message="${result.message ?? "N/A"}"');

    if (!mounted) return;

    final theme = Theme.of(context);
    final color = result.success
        ? theme.colorScheme.secondary
        : (result.status == AudioRouteStatus.pending
            ? Colors.orangeAccent
            : theme.colorScheme.error);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: color,
        content: Row(
          children: [
            Icon(
              result.success
                  ? Icons.check_circle_rounded
                  : (result.status == AudioRouteStatus.pending
                      ? Icons.hourglass_top_rounded
                      : Icons.error_rounded),
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.message ?? 'Routing status: ${result.status.name}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    _refreshRoute();
  }

  void _addLog(String msg) {
    final time = DateTime.now().toString().split(' ').last.substring(0, 8);
    setState(() {
      _consoleLogs.add('[$time] $msg');
    });

    // Auto-scroll to bottom of the console
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 100), () {
      if (_logScrollController.hasClients) {
        _logScrollController
            .jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });
  }

  IconData _getDeviceIcon(AudioOutputType type) {
    switch (type) {
      case AudioOutputType.speaker:
        return Icons.volume_up_rounded;
      case AudioOutputType.receiver:
        return Icons.phone_in_talk_rounded;
      case AudioOutputType.bluetooth:
        return Icons.bluetooth_audio_rounded;
      case AudioOutputType.wiredHeadset:
        return Icons.headset_rounded;
      case AudioOutputType.airpods:
        return Icons.headphones_rounded;
      case AudioOutputType.usbAudio:
        return Icons.usb_rounded;
      case AudioOutputType.carAudio:
        return Icons.directions_car_rounded;
      case AudioOutputType.hdmi:
        return Icons.settings_input_hdmi_rounded;
      case AudioOutputType.unknown:
        return Icons.device_unknown_rounded;
    }
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoIP Audio Route Manager'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _initialized ? _refreshRoute : null,
            tooltip: 'Refresh Routes',
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome & Setup Card
              if (!_initialized)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.settings_voice_rounded,
                          size: 48,
                          color: Color(0xFF6366F1),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Setup Platform Audio Routing',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Initialise the manager to register device observers and start managing audio states.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.bolt_rounded),
                          label: const Text('Initialize Manager',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: _initializeManager,
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                // VoIP Lifecycle Control Session Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'VOIP CALL LIFECYCLE',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _isCallActive
                                    ? theme.colorScheme.secondary.withAlpha(51)
                                    : Colors.white10,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: _isCallActive
                                          ? theme.colorScheme.secondary
                                          : Colors.grey,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isCallActive
                                        ? 'ACTIVE CALL'
                                        : 'IDLE / OFF',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _isCallActive
                                          ? theme.colorScheme.secondary
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.secondary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.call_rounded),
                                label: const Text('Start Call',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                onPressed:
                                    _isCallActive ? null : _startCallSession,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                  side: BorderSide(
                                      color: theme.colorScheme.error),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.call_end_rounded),
                                label: const Text('End Call',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                onPressed:
                                    _isCallActive ? _endCallSession : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Audio Routing Status Row
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ACTIVE ROUTE',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.secondary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_currentRoute != null)
                                Row(
                                  children: [
                                    Icon(_getDeviceIcon(_currentRoute!.type),
                                        size: 28, color: Colors.white),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _currentRoute!.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            _currentRoute!.type.name
                                                .toUpperCase(),
                                            style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              else
                                const Text('No active route',
                                    style: TextStyle(color: Colors.white38)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 16.0),
                        child: Column(
                          children: [
                            const Text(
                              'AUDIO FOCUS',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white70),
                            ),
                            const SizedBox(height: 10),
                            Icon(
                              _audioFocus
                                  ? Icons.lock_rounded
                                  : Icons.lock_open_rounded,
                              color: _audioFocus
                                  ? theme.colorScheme.secondary
                                  : Colors.white24,
                              size: 26,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Web details helper if needed
                if (kIsWeb) ...[
                  Card(
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                          color: theme.colorScheme.primary.withAlpha(128)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              color: Colors.amber),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Browsers restrict device details and names until microphone permissions are granted.',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.white70),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              _addLog(
                                  'Requesting mic permissions (Web only)...');
                              final ok = await _manager.requestPermissions();
                              _addLog('Mic permission response: $ok');
                              await _refreshRoute();
                            },
                            child: const Text('GRANT'),
                          ),
                          TextButton(
                            onPressed: () async {
                              final prefId = _currentRoute?.id;
                              _addLog('Opening W3C audio selector...');
                              final device = await _manager.selectAudioOutput(
                                  deviceId: prefId);
                              if (device != null) {
                                _addLog('W3C Device selected: ${device.name}');
                                await _refreshRoute();
                              }
                            },
                            child: const Text('SINK'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Device List Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'AVAILABLE DEVICES (${_devices.length})',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: Colors.white70, letterSpacing: 1.1),
                    ),
                    if (_currentRoute != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(50, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.settings_backup_restore_rounded,
                            size: 16),
                        label: const Text('Clear Override',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: _clearExplicitRoute,
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Devices ListView
                Expanded(
                  flex: 3,
                  child: ListView.builder(
                    itemCount: _devices.isEmpty ? 1 : _devices.length,
                    itemBuilder: (context, index) {
                      if (_devices.isEmpty) {
                        return const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Center(
                              child: Text(
                                'No output devices detected.',
                                style: TextStyle(color: Colors.white38),
                              ),
                            ),
                          ),
                        );
                      }

                      final device = _devices[index];
                      final isSelected = device.isSelected;

                      return Card(
                        color: isSelected
                            ? theme.colorScheme.primary.withAlpha(38)
                            : null,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: Icon(
                            _getDeviceIcon(device.type),
                            color: isSelected
                                ? theme.colorScheme.primary
                                : Colors.white70,
                          ),
                          title: Text(
                            device.name,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            device.type.name.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white54),
                          ),
                          trailing: isSelected
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                )
                              : OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                        color: theme.colorScheme.primary),
                                    foregroundColor: theme.colorScheme.primary,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                  ),
                                  onPressed: () => _selectDeviceRoute(device),
                                  child: const Text('SWITCH'),
                                ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // Quick Route Type Shortcuts
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildShortcutButton('Speaker', AudioOutputType.speaker),
                      const SizedBox(width: 8),
                      _buildShortcutButton(
                          'Earpiece', AudioOutputType.receiver),
                      const SizedBox(width: 8),
                      _buildShortcutButton(
                          'Bluetooth', AudioOutputType.bluetooth),
                      const SizedBox(width: 8),
                      _buildShortcutButton(
                          'Headset', AudioOutputType.wiredHeadset),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Console Debug Logs
              Text(
                'LIVE EVENTS & DEBUG LOGS',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: Colors.white70, letterSpacing: 1.1),
              ),
              const SizedBox(height: 6),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF020617), // Darker slate
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ListView.builder(
                    controller: _logScrollController,
                    itemCount: _consoleLogs.length,
                    itemBuilder: (context, index) {
                      return Text(
                        _consoleLogs[index],
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 12,
                          color: Color(0xFF38BDF8), // Light blue terminal text
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutButton(String text, AudioOutputType type) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF334155), // Slate 700
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      onPressed: _initialized ? () => _selectDeviceRouteType(type) : null,
      child: Text(text),
    );
  }
}
