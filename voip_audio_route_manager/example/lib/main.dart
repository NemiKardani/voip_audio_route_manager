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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark().copyWith(
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFF10B981),
          surface: const Color(0xFF1E293B),
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
  final List<String> _consoleLogs = [];
  final _logScrollController = ScrollController();
  
  late final List<StreamSubscription> _subscriptions;

  @override
  void initState() {
    super.initState();
    _addLog('App started. Tap "Initialize" to begin.');
  }

  Future<void> _initializeManager() async {
    try {
      await _manager.initialize(enableLogs: true);
      _addLog('VoipAudioRouteManager Initialized with logs.');
      
      // Start listening to streams
      _subscriptions = [
        _manager.audioDevicesStream.listen((devices) {
          setState(() {
            _devices = devices;
          });
          _addLog('Devices Stream: Received ${devices.length} devices');
        }),
        _manager.onRouteChanged.listen((route) {
          setState(() {
            _currentRoute = route;
          });
          _addLog('Route Changed Stream: ${route.name} (${route.type.name})');
          _refreshRoute(); // Update selected state list
        }),
        _manager.onDeviceConnected.listen((device) {
          _addLog('Device Connected Stream: ${device.name}');
        }),
        _manager.onDeviceDisconnected.listen((device) {
          _addLog('Device Disconnected Stream: ${device.name}');
        }),
        _manager.onAudioFocusChanged.listen((focused) {
          setState(() {
            _audioFocus = focused;
          });
          _addLog('Audio Focus Changed Stream: ${focused ? "Gained" : "Lost"}');
        }),
      ];

      final current = await _manager.currentAudioRoute();
      final available = await _manager.availableDevices();

      setState(() {
        _currentRoute = current;
        _devices = available;
        _initialized = true;
      });
      
      _addLog('Initial devices loaded: ${available.length} found.');
    } catch (e) {
      _addLog('Initialization error: $e');
    }
  }

  Future<void> _refreshRoute() async {
    final current = await _manager.currentAudioRoute();
    final available = await _manager.availableDevices();
    setState(() {
      _currentRoute = current;
      _devices = available;
    });
  }

  void _addLog(String msg) {
    final time = DateTime.now().toString().split(' ').last.substring(0, 8);
    setState(() {
      _consoleLogs.add('[$time] $msg');
    });
    // Auto-scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });
  }

  IconData _getDeviceIcon(AudioOutputType type) {
    switch (type) {
      case AudioOutputType.speaker:
        return Icons.volume_up_rounded;
      case AudioOutputType.receiver:
        return Icons.phone_android_rounded;
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initialized ? _refreshRoute : null,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Initialization status
            if (!_initialized)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Manager requires initialization to setup platform-specific routing listeners.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                        ),
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text('Initialize Manager'),
                        onPressed: _initializeManager,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Audio Focus & Current Route Card
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
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_currentRoute != null)
                              Row(
                                children: [
                                  Icon(_getDeviceIcon(_currentRoute!.type), size: 32, color: Colors.white),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _currentRoute!.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          _currentRoute!.type.name.toUpperCase(),
                                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            else
                              const Text('None active'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                      child: Column(
                        children: [
                          const Text('AUDIO FOCUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70)),
                          const SizedBox(height: 8),
                          Icon(
                            _audioFocus ? Icons.lock : Icons.lock_open,
                            color: _audioFocus ? theme.colorScheme.secondary : Colors.white24,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (kIsWeb) ...[
                Card(
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: theme.colorScheme.primary.withAlpha(128)),
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.amber),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'On Web, browser security hides output devices (e.g. Bluetooth) and labels until microphone permission is granted.',
                            style: TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            _addLog('Requesting microphone permission...');
                            final granted = await _manager.requestPermissions();
                            _addLog('Microphone permission result: ${granted ? "Granted" : "Denied"}');
                            if (granted) {
                              await _refreshRoute();
                            }
                          },
                          child: const Text('GRANT'),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: () async {
                            final currentId = _currentRoute?.id;
                            _addLog('Opening W3C Audio Output Selector (preferred device: $currentId)...');
                            final device = await _manager.selectAudioOutput(deviceId: currentId);
                            if (device != null) {
                              _addLog('W3C Device selected: ${device.name}');
                              await _refreshRoute();
                            } else {
                              _addLog('W3C Device selector closed or not supported.');
                            }
                          },
                          child: const Text('SELECT SINK'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              // Device List Header
              Text(
                'AVAILABLE OUTPUT DEVICES (${_devices.length})',
                style: theme.textTheme.titleSmall?.copyWith(color: Colors.white70, letterSpacing: 1.2),
              ),
              const SizedBox(height: 8),

              // Devices list
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
                    return Card(
                      color: device.isSelected
                          ? theme.colorScheme.primary.withAlpha(38)
                          : theme.cardTheme.color,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                          color: device.isSelected ? theme.colorScheme.primary : Colors.transparent,
                          width: 1.5,
                        ),
                        borderRadius: const BorderRadius.all(Radius.circular(12)),
                      ),
                      child: ListTile(
                        leading: Icon(_getDeviceIcon(device.type), color: device.isSelected ? theme.colorScheme.primary : Colors.white70),
                        title: Text(
                          device.name,
                          style: TextStyle(
                            fontWeight: device.isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(device.type.name.toUpperCase(), style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        trailing: device.isSelected
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              )
                            : OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: theme.colorScheme.primary),
                                  foregroundColor: theme.colorScheme.primary,
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                                ),
                                onPressed: () => _manager.setAudioRoute(device),
                                child: const Text('SWITCH'),
                              ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              
              // Route Shortcut Options
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildShortcutButton('Speaker', () => _manager.setAudioRouteType(AudioOutputType.speaker)),
                    const SizedBox(width: 8),
                    _buildShortcutButton('Earpiece', () => _manager.setAudioRouteType(AudioOutputType.receiver)),
                    const SizedBox(width: 8),
                    _buildShortcutButton('Bluetooth', () => _manager.setAudioRouteType(AudioOutputType.bluetooth)),
                    const SizedBox(width: 8),
                    _buildShortcutButton('Wired', () => _manager.setAudioRouteType(AudioOutputType.wiredHeadset)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Logging output console
            Text(
              'LIVE EVENTS & DEBUG LOGS',
              style: theme.textTheme.titleSmall?.copyWith(color: Colors.white70, letterSpacing: 1.2),
            ),
            const SizedBox(height: 6),
            Expanded(
              flex: 2,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF020617),
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
                        color: Color(0xFF38BDF8),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutButton(String text, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF334155),
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      onPressed: onPressed,
      child: Text(text),
    );
  }
}
