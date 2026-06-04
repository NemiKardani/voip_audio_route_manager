import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;
import 'package:voip_audio_route_manager_platform_interface/voip_audio_route_manager_platform_interface.dart';

/// Web implementation of [VoipAudioRouteManagerPlatform].
class FlutterVoipAudioRouteManagerWeb extends VoipAudioRouteManagerPlatform {
  /// Registers this class as the default instance of [VoipAudioRouteManagerPlatform].
  static void registerWith(Registrar registrar) {
    VoipAudioRouteManagerPlatform.instance = FlutterVoipAudioRouteManagerWeb();
  }

  String? _selectedDeviceId;
  final StreamController<List<AudioOutputDevice>> _devicesStreamController =
      StreamController<List<AudioOutputDevice>>.broadcast();
  final StreamController<AudioOutputDevice> _connectedStreamController =
      StreamController<AudioOutputDevice>.broadcast();
  final StreamController<AudioOutputDevice> _disconnectedStreamController =
      StreamController<AudioOutputDevice>.broadcast();
  final StreamController<AudioOutputDevice> _routeChangedStreamController =
      StreamController<AudioOutputDevice>.broadcast();
  final StreamController<bool> _audioFocusStreamController =
      StreamController<bool>.broadcast();

  List<AudioOutputDevice> _lastDevices = [];
  bool _initialized = false;
  web.MutationObserver? _mediaObserver;

  @override
  Future<void> initialize({bool enableLogs = false}) async {
    if (_initialized) return;
    _initialized = true;

    _injectInterceptionScript();

    final mediaDevices = _getMediaDevices();
    if (mediaDevices != null) {
      // Listen for device changes
      mediaDevices.addEventListener(
        'devicechange',
        (web.Event event) {
          _updateDevices();
        }.toJS,
      );
    }

    _setupMutationObserver();

    // Perform initial load
    await _updateDevices();
  }

  web.MediaDevices? _getMediaDevices() {
    try {
      return web.window.navigator.mediaDevices;
    } catch (_) {
      return null;
    }
  }

  Future<void> _updateDevices() async {
    final currentDevices = await availableDevices();

    // Compare to detect connections/disconnections
    final oldMap = {for (var d in _lastDevices) d.id: d};
    final newMap = {for (var d in currentDevices) d.id: d};

    // Device connected
    for (var id in newMap.keys) {
      if (!oldMap.containsKey(id)) {
        _connectedStreamController.add(newMap[id]!);
      }
    }

    // Device disconnected
    for (var id in oldMap.keys) {
      if (!newMap.containsKey(id)) {
        _disconnectedStreamController.add(oldMap[id]!);
      }
    }

    _lastDevices = currentDevices;
    _devicesStreamController.add(currentDevices);

    // If selected device is no longer available, default to the first one (usually speaker)
    if (_selectedDeviceId != null && !newMap.containsKey(_selectedDeviceId)) {
      if (currentDevices.isNotEmpty) {
        _selectedDeviceId = currentDevices.first.id;
        _routeChangedStreamController.add(currentDevices.first);
      } else {
        _selectedDeviceId = null;
      }
    }

    if (_selectedDeviceId != null &&
        _selectedDeviceId != 'default' &&
        _selectedDeviceId!.isNotEmpty) {
      _applySinkIdToAllMediaElements(_selectedDeviceId!);
    }
  }

  @override
  Future<List<AudioOutputDevice>> availableDevices() async {
    final mediaDevices = _getMediaDevices();
    if (mediaDevices == null) {
      // Fallback in unsupported context / HTTP
      return [
        AudioOutputDevice(
          id: 'default',
          name: 'System Default Audio Device',
          type: AudioOutputType.speaker,
          isSelected:
              _selectedDeviceId == null || _selectedDeviceId == 'default',
        ),
      ];
    }

    try {
      final devicesPromise = mediaDevices.enumerateDevices();
      final jsDevicesList = await devicesPromise.toDart;
      final dartList = jsDevicesList.toDart;

      final List<AudioOutputDevice> list = [];
      for (final info in dartList) {
        // Only return audiooutput devices
        if (info.kind == 'audiooutput') {
          final id = info.deviceId;
          final label = info.label.isEmpty ? 'Audio Output' : info.label;
          final type = _inferType(label);
          final isSelected = id == _selectedDeviceId ||
              (_selectedDeviceId == null && list.isEmpty);

          list.add(
            AudioOutputDevice(
              id: id,
              name: label,
              type: type,
              isSelected: isSelected,
            ),
          );
        }
      }

      // If no audiooutput devices listed (sometimes restricted by sandbox)
      if (list.isEmpty) {
        list.add(
          AudioOutputDevice(
            id: 'default',
            name: 'System Default Audio Device',
            type: AudioOutputType.speaker,
            isSelected:
                _selectedDeviceId == null || _selectedDeviceId == 'default',
          ),
        );
      }

      return list;
    } catch (_) {
      return [
        AudioOutputDevice(
          id: 'default',
          name: 'System Default Audio Device',
          type: AudioOutputType.speaker,
          isSelected:
              _selectedDeviceId == null || _selectedDeviceId == 'default',
        ),
      ];
    }
  }

  AudioOutputType _inferType(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('speaker') || lower.contains('internal')) {
      return AudioOutputType.speaker;
    } else if (lower.contains('bluetooth') ||
        lower.contains('buds') ||
        lower.contains('pods') ||
        lower.contains('hands-free') ||
        lower.contains('hfp')) {
      if (lower.contains('airpods')) {
        return AudioOutputType.airpods;
      }
      return AudioOutputType.bluetooth;
    } else if (lower.contains('headset') ||
        lower.contains('headphone') ||
        lower.contains('jack') ||
        lower.contains('wired')) {
      return AudioOutputType.wiredHeadset;
    } else if (lower.contains('usb')) {
      return AudioOutputType.usbAudio;
    } else if (lower.contains('hdmi')) {
      return AudioOutputType.hdmi;
    } else if (lower.contains('car')) {
      return AudioOutputType.carAudio;
    } else if (lower.contains('receiver') || lower.contains('earpiece')) {
      return AudioOutputType.receiver;
    }
    return AudioOutputType.unknown;
  }

  @override
  Future<AudioOutputDevice?> currentAudioRoute() async {
    final list = await availableDevices();
    if (list.isEmpty) return null;
    return list.firstWhere(
      (d) => d.isSelected,
      orElse: () => list.first,
    );
  }

  @override
  Future<void> setAudioRoute(String id) async {
    final list = await availableDevices();
    final match = list.firstWhere((d) => d.id == id, orElse: () => list.first);
    _selectedDeviceId = match.id;
    _routeChangedStreamController.add(match.copyWith(isSelected: true));
    if (_selectedDeviceId != null &&
        _selectedDeviceId != 'default' &&
        _selectedDeviceId!.isNotEmpty) {
      _applySinkIdToAllMediaElements(_selectedDeviceId!);
    }
    await _updateDevices();
  }

  @override
  Future<void> setAudioRouteType(String type) async {
    final list = await availableDevices();
    final match = list.firstWhere(
      (d) => d.type.name == type,
      orElse: () => list.first,
    );
    await setAudioRoute(match.id);
  }

  @override
  Future<void> setAudioRouteByName(String name) async {
    final list = await availableDevices();
    final match = list.firstWhere(
      (d) => d.name.toLowerCase().contains(name.toLowerCase()),
      orElse: () => list.first,
    );
    await setAudioRoute(match.id);
  }

  @override
  Stream<List<AudioOutputDevice>> get audioDevicesStream =>
      _devicesStreamController.stream;

  @override
  Stream<AudioOutputDevice> get onDeviceConnected =>
      _connectedStreamController.stream;

  @override
  Stream<AudioOutputDevice> get onDeviceDisconnected =>
      _disconnectedStreamController.stream;

  @override
  Stream<AudioOutputDevice> get onRouteChanged =>
      _routeChangedStreamController.stream;

  @override
  Stream<bool> get onAudioFocusChanged => _audioFocusStreamController.stream;

  @override
  Future<bool> requestPermissions() async {
    final mediaDevices = _getMediaDevices();
    if (mediaDevices == null) return false;
    try {
      final constraints = web.MediaStreamConstraints(audio: true.toJS);
      final streamPromise = mediaDevices.getUserMedia(constraints);
      final stream = await streamPromise.toDart;
      final tracks = stream.getTracks().toDart;
      for (var i = 0; i < tracks.length; i++) {
        tracks[i].stop();
      }
      await _updateDevices();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _injectInterceptionScript() {
    try {
      final script =
          web.document.createElement('script') as web.HTMLScriptElement;
      script.text = '''
(function() {
  if (window._voipAudioRouteManagerInitialized) return;
  window._voipAudioRouteManagerInitialized = true;

  const trackedMediaElements = [];
  const trackedAudioContexts = [];
  window._voipAudioRouteManagerCurrentDeviceId = '';

  function applySinkIdToElement(element, deviceId) {
    if (!element || typeof element.setSinkId !== 'function') return;
    const targetId = (!deviceId || deviceId === 'default') ? '' : deviceId;
    element.setSinkId(targetId).catch(err => {
      console.warn('Failed to set sink ID on HTMLMediaElement:', err);
    });
  }

  function applySinkIdToContext(context, deviceId) {
    if (!context || typeof context.setSinkId !== 'function') return;
    const targetId = (!deviceId || deviceId === 'default') ? '' : deviceId;
    context.setSinkId(targetId).catch(err => {
      console.warn('Failed to set sink ID on AudioContext:', err);
    });
  }

  function trackMediaElement(element) {
    try {
      if (typeof WeakRef !== 'undefined') {
        trackedMediaElements.push(new WeakRef(element));
      } else {
        trackedMediaElements.push({ deref: () => element });
      }
      const currentId = window._voipAudioRouteManagerCurrentDeviceId;
      if (currentId && currentId !== 'default') {
        applySinkIdToElement(element, currentId);
      }
    } catch (e) {
      console.warn('Failed to track media element:', e);
    }
  }

  try {
    const originalCreateElement = document.createElement;
    document.createElement = function(tagName, options) {
      const element = originalCreateElement.call(document, tagName, options);
      if (element && (tagName.toLowerCase() === 'audio' || tagName.toLowerCase() === 'video')) {
        trackMediaElement(element);
      }
      return element;
    };
  } catch (e) {
    console.warn('Failed to intercept document.createElement:', e);
  }

  try {
    const OriginalAudio = window.Audio;
    if (OriginalAudio) {
      window.Audio = function(...args) {
        const element = new OriginalAudio(...args);
        trackMediaElement(element);
        return element;
      };
      window.Audio.prototype = OriginalAudio.prototype;
    }
  } catch (e) {
    console.warn('Failed to intercept window.Audio:', e);
  }

  try {
    const OriginalAudioContext = window.AudioContext || window.webkitAudioContext;
    if (OriginalAudioContext) {
      const ProxyAudioContext = new Proxy(OriginalAudioContext, {
        construct(target, argumentsList, newTarget) {
          const context = Reflect.construct(target, argumentsList, newTarget);
          try {
            if (typeof WeakRef !== 'undefined') {
              trackedAudioContexts.push(new WeakRef(context));
            } else {
              trackedAudioContexts.push({ deref: () => context });
            }
            const currentId = window._voipAudioRouteManagerCurrentDeviceId;
            if (currentId && currentId !== 'default') {
              applySinkIdToContext(context, currentId);
            }
          } catch (e) {
            console.warn('Failed to track AudioContext:', e);
          }
          return context;
        }
      });
      if (window.AudioContext) window.AudioContext = ProxyAudioContext;
      if (window.webkitAudioContext) window.webkitAudioContext = ProxyAudioContext;
    }
  } catch (e) {
    console.warn('Failed to intercept AudioContext:', e);
  }

  window._voipAudioRouteManagerSetSinkId = function(deviceId) {
    window._voipAudioRouteManagerCurrentDeviceId = deviceId;

    for (let i = trackedMediaElements.length - 1; i >= 0; i--) {
      const ref = trackedMediaElements[i];
      const element = ref.deref();
      if (element) {
        applySinkIdToElement(element, deviceId);
      } else {
        trackedMediaElements.splice(i, 1);
      }
    }

    try {
      const audios = document.querySelectorAll('audio');
      for (let i = 0; i < audios.length; i++) {
        applySinkIdToElement(audios.item(i), deviceId);
      }
      const videos = document.querySelectorAll('video');
      for (let i = 0; i < videos.length; i++) {
        applySinkIdToElement(videos.item(i), deviceId);
      }
    } catch (e) {}

    for (let i = trackedAudioContexts.length - 1; i >= 0; i--) {
      const ref = trackedAudioContexts[i];
      const context = ref.deref();
      if (context) {
        applySinkIdToContext(context, deviceId);
      } else {
        trackedAudioContexts.splice(i, 1);
      }
    }
  };
})();
      ''';
      web.document.head?.appendChild(script);
    } catch (_) {}
  }

  void _applySinkIdToAllMediaElements(String deviceId) {
    try {
      final windowJS = web.window as JSObject;
      if (windowJS.hasProperty('_voipAudioRouteManagerSetSinkId'.toJS).toDart) {
        windowJS.callMethod(
            '_voipAudioRouteManagerSetSinkId'.toJS, deviceId.toJS);
      } else {
        // Fallback
        final doc = web.document;
        final audios = doc.querySelectorAll('audio');
        for (var i = 0; i < audios.length; i++) {
          _applySinkIdToElement(audios.item(i) as JSObject, deviceId);
        }
        final videos = doc.querySelectorAll('video');
        for (var i = 0; i < videos.length; i++) {
          _applySinkIdToElement(videos.item(i) as JSObject, deviceId);
        }
      }
    } catch (_) {}
  }

  void _applySinkIdToElement(JSObject element, String deviceId) {
    try {
      if (element.hasProperty('setSinkId'.toJS).toDart) {
        element.callMethod<JSPromise?>('setSinkId'.toJS, deviceId.toJS);
      }
    } catch (_) {}
  }

  void _setupMutationObserver() {
    if (_mediaObserver != null) return;
    try {
      _mediaObserver = web.MutationObserver(
          (JSArray mutations, web.MutationObserver observer) {
        final currentId = _selectedDeviceId;
        if (currentId == null || currentId == 'default' || currentId.isEmpty)
          return;

        final list = mutations.toDart;
        for (var i = 0; i < list.length; i++) {
          final mutation = list[i] as web.MutationRecord;
          final addedNodes = mutation.addedNodes;
          for (var j = 0; j < addedNodes.length; j++) {
            final node = addedNodes.item(j);
            if (node != null) {
              _checkAndApplySinkIdToNode(node, currentId);
            }
          }
        }
      }.toJS);

      final config = web.MutationObserverInit(
        childList: true,
        subtree: true,
      );
      _mediaObserver!.observe(web.document.body!, config);
    } catch (_) {}
  }

  void _checkAndApplySinkIdToNode(web.Node node, String deviceId) {
    if (node.nodeType == web.Node.ELEMENT_NODE) {
      final element = node as web.Element;
      final tagName = element.tagName.toLowerCase();
      if (tagName == 'audio' || tagName == 'video') {
        _applySinkIdToElement(element as JSObject, deviceId);
      }

      final audios = element.querySelectorAll('audio');
      for (var i = 0; i < audios.length; i++) {
        _applySinkIdToElement(audios.item(i) as JSObject, deviceId);
      }
      final videos = element.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        _applySinkIdToElement(videos.item(i) as JSObject, deviceId);
      }
    }
  }

  @override
  Future<AudioOutputDevice?> selectAudioOutput({String? deviceId}) async {
    final mediaDevices = _getMediaDevices();
    if (mediaDevices == null) return null;

    final mediaDevicesJS = mediaDevices as JSObject;
    if (mediaDevicesJS.hasProperty('selectAudioOutput'.toJS).toDart) {
      try {
        JSPromise promise;
        if (deviceId != null && deviceId.isNotEmpty) {
          final options = JSObject();
          options.setProperty('deviceId'.toJS, deviceId.toJS);
          promise = mediaDevicesJS.callMethod<JSPromise>(
              'selectAudioOutput'.toJS, options);
        } else {
          promise =
              mediaDevicesJS.callMethod<JSPromise>('selectAudioOutput'.toJS);
        }
        final deviceInfo = await promise.toDart;
        final deviceInfoJS = deviceInfo as JSObject;

        final idVal = deviceInfoJS.getProperty('deviceId'.toJS);
        final labelVal = deviceInfoJS.getProperty('label'.toJS);

        final id = idVal is JSString ? idVal.toDart : '';
        final label = labelVal is JSString ? labelVal.toDart : 'Audio Output';

        final device = AudioOutputDevice(
          id: id,
          name: label.isEmpty ? 'Audio Output' : label,
          type: _inferType(label),
          isSelected: true,
        );

        await setAudioRoute(device.id);
        return device;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
