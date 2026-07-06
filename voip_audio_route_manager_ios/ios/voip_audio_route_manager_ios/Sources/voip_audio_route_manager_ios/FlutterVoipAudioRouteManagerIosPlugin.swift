import Flutter
import UIKit
import AVFoundation
import CallKit

public class FlutterVoipAudioRouteManagerIosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var channel: FlutterMethodChannel?
  private var enableLogs: Bool = false
  private var isListening = false
  private var preferredDeviceId: String?
  private var preferredDeviceType: String?

  private struct RouteAttempt {
    let success: Bool
    let status: String
    let message: String?
    let errorCode: String?
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "voip_audio_route_manager", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "voip_audio_route_manager/events", binaryMessenger: registrar.messenger())

    let instance = FlutterVoipAudioRouteManagerIosPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)
  }

  // MARK: - Plugin lifecycle

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    NotificationCenter.default.removeObserver(self)
    channel?.setMethodCallHandler(nil)
    channel = nil
    eventSink = nil
    isListening = false
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()

    switch call.method {
    case "initialize":
      if let args = call.arguments as? [String: Any],
         let enableLogs = args["enableLogs"] as? Bool {
        self.enableLogs = enableLogs
      }
      ensurePlayAndRecordCategory(session: session)
      setupNotifications()
      result(nil)
    case "availableDevices":
      result(getAvailableDevices(session: session))
    case "currentAudioRoute":
      result(getCurrentAudioRoute(session: session))
    case "startCallSession":
      preferredDeviceType = nil
      preferredDeviceId = nil
      do {
        try session.overrideOutputAudioPort(.none)
        try session.setPreferredInput(nil)
      } catch {
        log("startCallSession: failed to reset audio port/input: \(error.localizedDescription)")
      }
      ensurePlayAndRecordCategory(session: session)
      result(nil)
    case "endCallSession":
      endCallSession(session: session)
      result(nil)
    case "setAudioRoute":
      if let args = call.arguments as? [String: Any],
         let deviceId = args["id"] as? String {
        setAudioRoute(deviceId: deviceId, session: session, result: result)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Device ID required", details: nil))
      }
    case "setAudioRouteType":
      if let args = call.arguments as? [String: Any],
         let typeStr = args["type"] as? String {
        setRouteByType(typeStr: typeStr, session: session, result: result)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Type required", details: nil))
      }
    case "setAudioRouteByName":
      if let args = call.arguments as? [String: Any],
         let name = args["name"] as? String {
        setRouteByName(name: name, session: session, result: result)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Name required", details: nil))
      }
    case "selectAudioRoute":
      if let args = call.arguments as? [String: Any],
         let deviceId = args["id"] as? String {
        selectAudioRoute(deviceId: deviceId, session: session, result: result)
      } else {
        result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(session: session), message: "Device ID required", errorCode: "INVALID_ARGUMENTS"))
      }
    case "selectAudioRouteType":
      if let args = call.arguments as? [String: Any],
         let typeStr = args["type"] as? String {
        selectRouteByType(typeStr: typeStr, session: session, result: result)
      } else {
        result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(session: session), message: "Type required", errorCode: "INVALID_ARGUMENTS"))
      }
    case "selectAudioRouteByName":
      if let args = call.arguments as? [String: Any],
         let name = args["name"] as? String {
        selectRouteByName(name: name, session: session, result: result)
      } else {
        result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(session: session), message: "Name required", errorCode: "INVALID_ARGUMENTS"))
      }
    case "clearAudioRoute":
      clearAudioRoute(session: session)
      result(nil)
    case "switchToSpeaker":
      result(routeToSpeaker())
    case "switchToEarpiece":
      result(routeToEarpiece())
    case "getAvailableRoutes":
      result(getAvailableRoutesList(session: session))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    isListening = true
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    isListening = false
    self.eventSink = nil
    return nil
  }

  private func log(_ message: String) {
    if enableLogs {
      print("[VoipAudio] [iOS] \(message)")
    }
  }

  private func setupNotifications() {
    NotificationCenter.default.removeObserver(self)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
  }

  // MARK: - Notification handling (thread-safe entry points)
  //
  // AVAudioSession posts these notifications on an arbitrary (often background)
  // thread. All Flutter channel calls and all mutation of shared state
  // (preferredDeviceType / preferredDeviceId) must happen on the main thread,
  // otherwise this plugin has a data race with `applyAudioRoute`, which runs
  // on the main thread via `handle(_:result:)`. That race is the most likely
  // cause of routes silently reverting to Bluetooth right after being forced
  // to the earpiece.

  @objc private func handleRouteChange(notification: Notification) {
    if Thread.isMainThread {
      handleRouteChangeOnMain(notification: notification)
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.handleRouteChangeOnMain(notification: notification)
      }
    }
  }

  private func handleRouteChangeOnMain(notification: Notification) {
    log("Audio route changed notification received.")
    let session = AVAudioSession.sharedInstance()

    let currentOutput = session.currentRoute.outputs.first
    let routeStr: String
    if let portType = currentOutput?.portType {
      switch portType {
      case .builtInSpeaker:   routeStr = "speaker"
      case .builtInReceiver:  routeStr = "earpiece"
      case .bluetoothHFP,
           .bluetoothA2DP,
           .bluetoothLE:      routeStr = "bluetooth"
      case .headphones,
           .headsetMic:       routeStr = "wired_headset"
      default:                routeStr = "unknown"
      }
    } else {
      routeStr = "unknown"
    }

    // EXPERIMENTAL — see method doc comment below for caveats. Reacts to
    // undocumented CallKit/AVAudioSession menu behavior; verify on-device.
    reinforceBluetoothPreferredInputIfActive(session: session)

    channel?.invokeMethod("onAudioRouteChanged", arguments: ["route": routeStr])

    guard isListening, let sink = eventSink else { return }
    let devices = getAvailableDevices(session: session)
    sink(["event": "devices_changed", "devices": devices])

    var eventData: [String: Any] = [
      "event": "route_changed",
      "route": routeStr
    ]
    if let route = getCurrentAudioRoute(session: session) {
      eventData["device"] = route
    }
    sink(eventData)
  }

  @objc private func handleInterruption(notification: Notification) {
    if Thread.isMainThread {
      handleInterruptionOnMain(notification: notification)
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.handleInterruptionOnMain(notification: notification)
      }
    }
  }

  private func handleInterruptionOnMain(notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }

    log("Audio session interruption notification received: \(type == .began ? "Began" : "Ended")")
    guard isListening, let sink = eventSink else { return }

    if type == .began {
      sink(["event": "audio_focus_changed", "focused": false])
    } else {
      if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        if options.contains(.shouldResume) {
          sink(["event": "audio_focus_changed", "focused": true])
        }
      }
    }
  }

  private func mapPortType(_ portType: AVAudioSession.Port, portName: String) -> String {
    if portType == .builtInSpeaker {
      return "speaker"
    } else if portType == .builtInReceiver {
      return "receiver"
    } else if portType == .bluetoothHFP || portType == .bluetoothLE || portType == .bluetoothA2DP {
      return portName.lowercased().contains("airpods") ? "airpods" : "bluetooth"
    } else if portType == .headsetMic || portType == .lineIn || portType == .headphones || portType == .lineOut {
      return "wiredHeadset"
    } else if portType == .usbAudio {
      return "usbAudio"
    } else if portType == .carAudio {
      return "carAudio"
    }
    return "unknown"
  }

  private func getAvailableDevices(session: AVAudioSession) -> [[String: Any]] {
    var rawDevices: [[String: Any]] = []

    // 1. Built-in Speaker (Always available)
    rawDevices.append([
      "id": "speaker",
      "name": "Speaker",
      "type": "speaker"
    ])

    // 2. Built-in Receiver (Earpiece) - Only available on iPhone natively when no external device is connected
    // or if it's the currently active route.
    let showEarpiece = UIDevice.current.userInterfaceIdiom == .phone &&
      (!hasExternalDeviceConnected(session: session) || isReceiverActive(session: session))
    if showEarpiece {
      rawDevices.append([
        "id": "receiver",
        "name": "Earpiece",
        "type": "receiver"
      ])
    }

    // 3. Bluetooth and Wired outputs from available inputs
    if let availableInputs = session.availableInputs {
      for input in availableInputs {
        let portType = input.portType
        var type = "unknown"
        let id = input.uid
        let name = input.portName

        if portType == .bluetoothHFP || portType == .bluetoothLE {
          type = name.lowercased().contains("airpods") ? "airpods" : "bluetooth"
        } else if portType == .headsetMic || portType == .lineIn {
          type = "wiredHeadset"
        } else if portType == .usbAudio {
          type = "usbAudio"
        } else if portType == .carAudio {
          type = "carAudio"
        } else {
          continue // skip internal mics
        }

        rawDevices.append([
          "id": id,
          "name": name,
          "type": type
        ])
      }
    }

    // 4. Double check for Bluetooth A2DP headphones (which don't appear in inputs)
    for output in session.currentRoute.outputs {
      if output.portType == .bluetoothA2DP {
        let id = output.uid
        let name = output.portName
        let type = name.lowercased().contains("airpods") ? "airpods" : "bluetooth"

        // Add if not already listed (deduplicate by name to prevent showing duplicates for same device)
        if !rawDevices.contains(where: { ($0["name"] as? String) == name }) {
          rawDevices.append([
            "id": id,
            "name": name,
            "type": type
          ])
        }
      }
    }

    // Update preferredDeviceType based on current state and connectivity
    let hasBluetooth = rawDevices.contains {
      let t = $0["type"] as? String
      return t == "bluetooth" || t == "airpods"
    }
    let hasWired = rawDevices.contains {
      let t = $0["type"] as? String
      return t == "wiredHeadset" || t == "usbAudio"
    }

    if let preferredType = preferredDeviceType {
      var isPreferredConnected = false
      if preferredType == "speaker" || preferredType == "receiver" {
        isPreferredConnected = true
      } else {
        isPreferredConnected = rawDevices.contains { ($0["type"] as? String) == preferredType }
      }

      if !isPreferredConnected {
        log("Preferred device type \(preferredType) is no longer connected. Clearing preference.")
        preferredDeviceType = nil
        preferredDeviceId = nil
      }
    }

    // Incur active system route details
    var currentActiveType = "unknown"
    var currentActiveId = ""
    for output in session.currentRoute.outputs {
      let mapped = mapPortType(output.portType, portName: output.portName)
      if mapped != "unknown" {
        currentActiveType = mapped
        currentActiveId = output.uid
        break
      }
    }

    // Auto-override preference on physical routing events
    if preferredDeviceType == nil && currentActiveType != "unknown" {
      preferredDeviceType = currentActiveType
      preferredDeviceId = currentActiveId
      log("Inferred preferredDeviceType from active output: \(currentActiveType)")
    } else if let preferredType = preferredDeviceType, currentActiveType != "unknown" {
      if preferredType != currentActiveType {
        var shouldOverride = false
        if currentActiveType == "wiredHeadset" || currentActiveType == "usbAudio" ||
           currentActiveType == "bluetooth" || currentActiveType == "airpods" || currentActiveType == "carAudio" {
          shouldOverride = true
        } else if currentActiveType == "speaker" || currentActiveType == "receiver" {
          let wasHeadset = preferredType == "bluetooth" || preferredType == "airpods" || preferredType == "wiredHeadset" || preferredType == "usbAudio"
          if wasHeadset {
            shouldOverride = true
          } else {
            shouldOverride = false
          }
        }

        if shouldOverride {
          log("System routed to \(currentActiveType) overriding preference \(preferredType)")
          preferredDeviceType = currentActiveType
          preferredDeviceId = currentActiveId
        }
      }
    }

    var finalDevices: [[String: Any]] = []
    for device in rawDevices {
      let devId = device["id"] as? String ?? ""
      let devType = device["type"] as? String ?? ""

      var isSelected = false
      if let preferredType = preferredDeviceType {
        if preferredType == "bluetooth" || preferredType == "airpods" {
          isSelected = (devType == "bluetooth" || devType == "airpods")
        } else if preferredType == "wiredHeadset" || preferredType == "usbAudio" {
          isSelected = (devType == "wiredHeadset" || devType == "usbAudio")
        } else {
          isSelected = (devType == preferredType)
        }
      } else {
        if currentActiveId.isEmpty {
          if UIDevice.current.userInterfaceIdiom == .phone {
            isSelected = (devType == "receiver")
          } else {
            isSelected = (devType == "speaker")
          }
        } else {
          isSelected = (devId == currentActiveId)
        }
      }

      finalDevices.append([
        "id": devId,
        "name": device["name"] as? String ?? "",
        "type": devType,
        "isSelected": isSelected
      ])
    }

    return finalDevices
  }

  private func getCurrentAudioRoute(session: AVAudioSession) -> [String: Any]? {
    let devices = getAvailableDevices(session: session)
    let selected = devices.first(where: { ($0["isSelected"] as? Bool) == true }) ?? devices.first
    let outputs = session.currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
    log("getCurrentAudioRoute: preferredType=\(preferredDeviceType ?? "nil"), active outputs=\(outputs), selected=\(selected ?? [:])")
    return selected
  }

  private func isSpeakerActive(session: AVAudioSession) -> Bool {
    return session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
  }

  private func isReceiverActive(session: AVAudioSession) -> Bool {
    return session.currentRoute.outputs.contains { $0.portType == .builtInReceiver }
  }

  private func hasExternalDeviceConnected(session: AVAudioSession) -> Bool {
    if let availableInputs = session.availableInputs {
      for input in availableInputs {
        let portType = input.portType
        if portType == .bluetoothHFP || portType == .bluetoothLE ||
           portType == .headsetMic || portType == .lineIn ||
           portType == .usbAudio || portType == .carAudio {
          return true
        }
      }
    }
    for output in session.currentRoute.outputs {
      let portType = output.portType
      if portType == .bluetoothA2DP ||
         portType == .bluetoothLE ||
         portType == .bluetoothHFP ||
         portType == .headphones ||
         portType == .lineOut ||
         portType == .usbAudio ||
         portType == .carAudio {
        return true
      }
    }
    return false
  }

  private func isPortActive(session: AVAudioSession, portUID: String) -> Bool {
    return session.currentRoute.outputs.contains { $0.uid == portUID } ||
           session.currentRoute.inputs.contains { $0.uid == portUID }
  }

  // MARK: - Category management

  private func ensurePlayAndRecordCategory(session: AVAudioSession, options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP]) {
    log("ensurePlayAndRecordCategory starting. Category: \(session.category.rawValue), Options: \(session.categoryOptions), requestedOptions: \(options)")

    // If CallKit currently owns an active call, avoid fighting it for session
    // configuration. CallKit configures AVAudioSession itself around provider
    // callbacks (didActivate/didDeactivate); mutating category here concurrently
    // can silently lose to CallKit's own configuration, which is a common source
    // of routes that appear to "not stick".
    let callObserver = CXCallObserver()
    if !callObserver.calls.isEmpty {
      log("ensurePlayAndRecordCategory: Active CallKit call detected — skipping category mutation to avoid conflicting with CallKit's own AVAudioSession configuration.")
      return
    }

    if session.category != .playAndRecord || session.categoryOptions != options {
      do {
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        if shouldManageActiveState() {
          try session.setActive(true, options: .notifyOthersOnDeactivation)
        }
        log("ensurePlayAndRecordCategory: AVAudioSession category set to playAndRecord with voiceChat mode, options: \(options).")
      } catch {
        log("ensurePlayAndRecordCategory: Failed to set AVAudioSession category to playAndRecord: \(error.localizedDescription)")
      }
    }
  }

  private func setAudioRoute(deviceId: String, session: AVAudioSession, result: FlutterResult) {
    let attempt = applyAudioRoute(deviceId: deviceId, session: session)
    if attempt.success {
      result(nil)
    } else {
      result(FlutterError(code: attempt.errorCode ?? "AVAUDIOSESSION_ERROR", message: attempt.message, details: nil))
    }
  }

  private func applyAudioRoute(deviceId: String, session: AVAudioSession) -> RouteAttempt {
    do {
      if deviceId == "speaker" {
        // Bluetooth eligibility doesn't matter here since overrideOutputAudioPort(.speaker)
        // is an explicit forced override that wins regardless of category options.
        ensurePlayAndRecordCategory(session: session, options: [.allowBluetooth, .allowBluetoothA2DP])
        try session.overrideOutputAudioPort(.speaker)
        preferredDeviceId = "speaker"
        preferredDeviceType = "speaker"
        log("Speaker override activated. preferredDeviceType set to speaker")
        return RouteAttempt(success: true, status: "success", message: "Audio route changed successfully.", errorCode: nil)
      } else if deviceId == "receiver" {
        // IMPORTANT: There is no explicit "earpiece" override in AVAudioSession.
        // overrideOutputAudioPort(.none) only resumes automatic routing, and automatic
        // routing always prefers a connected Bluetooth device over the built-in receiver.
        // The only way to force the earpiece while BT is still connected is to make BT
        // ineligible first by removing .allowBluetooth / .allowBluetoothA2DP from the
        // category options, then let automatic routing fall back to the receiver.
        ensurePlayAndRecordCategory(session: session, options: [])
        try session.overrideOutputAudioPort(.none)
        if let availableInputs = session.availableInputs,
           let builtInMic = availableInputs.first(where: { $0.portType == .builtInMic }) {
          try session.setPreferredInput(builtInMic)
          log("Bluetooth disallowed, speaker override cleared, preferred input set to builtInMic (earpiece forced).")
        } else {
          try session.setPreferredInput(nil)
          log("Bluetooth disallowed, speaker override cleared, preferred input cleared (earpiece default).")
        }
        preferredDeviceId = "receiver"
        preferredDeviceType = "receiver"
        return RouteAttempt(success: true, status: "success", message: "Audio route changed successfully.", errorCode: nil)
      } else {
        // Bluetooth / Wired Headset
        if let availableInputs = session.availableInputs {
          if let match = availableInputs.first(where: { $0.uid == deviceId }) {
            // Re-enable Bluetooth eligibility in case a prior "receiver" route disabled it.
            ensurePlayAndRecordCategory(session: session, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.overrideOutputAudioPort(.none)
            try session.setPreferredInput(match)
            preferredDeviceId = deviceId
            preferredDeviceType = mapPortType(match.portType, portName: match.portName)
            log("Preferred input set: \(match.portName). preferredDeviceType set to \(preferredDeviceType ?? "nil")")
            return RouteAttempt(success: true, status: "success", message: "Audio route changed successfully.", errorCode: nil)
          }
        }
        return RouteAttempt(success: false, status: "notFound", message: "Requested device not found in available inputs", errorCode: "DEVICE_NOT_AVAILABLE")
      }
    } catch {
      return RouteAttempt(success: false, status: "error", message: "Failed to switch audio route: \(error.localizedDescription)", errorCode: "AVAUDIOSESSION_ERROR")
    }
  }

  private func setRouteByType(typeStr: String, session: AVAudioSession, result: FlutterResult) {
    if typeStr == "receiver" && UIDevice.current.userInterfaceIdiom != .phone {
      setAudioRoute(deviceId: "receiver", session: session, result: result)
      return
    }
    let devices = getAvailableDevices(session: session)
    if let match = devices.first(where: { ($0["type"] as? String) == typeStr }),
       let id = match["id"] as? String {
      setAudioRoute(deviceId: id, session: session, result: result)
    } else {
      result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No device matching type \(typeStr)", details: nil))
    }
  }

  private func setRouteByName(name: String, session: AVAudioSession, result: FlutterResult) {
    let devices = getAvailableDevices(session: session)
    if let match = devices.first(where: { ($0["name"] as? String)?.localizedCaseInsensitiveContains(name) ?? false }),
       let id = match["id"] as? String {
      setAudioRoute(deviceId: id, session: session, result: result)
    } else {
      result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No device matching name \(name)", details: nil))
    }
  }

  private func selectAudioRoute(deviceId: String, session: AVAudioSession, result: FlutterResult) {
    let requested = getAvailableDevices(session: session).first { ($0["id"] as? String) == deviceId }
    guard let requestedDevice = requested else {
      result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(session: session), message: "No audio output device matched the requested ID.", errorCode: nil))
      return
    }

    let attempt = applyAudioRoute(deviceId: deviceId, session: session)
    result(routeResult(success: attempt.success, status: attempt.status, requestedDevice: requestedDevice, actualDevice: getCurrentAudioRoute(session: session), message: attempt.message, errorCode: attempt.errorCode))
  }

  private func selectRouteByType(typeStr: String, session: AVAudioSession, result: FlutterResult) {
    if typeStr == "receiver" && UIDevice.current.userInterfaceIdiom != .phone {
      let attempt = applyAudioRoute(deviceId: "receiver", session: session)
      result(routeResult(success: attempt.success, status: attempt.status, requestedDevice: nil, actualDevice: getCurrentAudioRoute(session: session), message: attempt.message, errorCode: attempt.errorCode))
      return
    }
    let requested = getAvailableDevices(session: session).first { ($0["type"] as? String) == typeStr }
    guard let requestedDevice = requested,
          let id = requestedDevice["id"] as? String else {
      result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(session: session), message: "No audio output device matched type \(typeStr).", errorCode: nil))
      return
    }

    let attempt = applyAudioRoute(deviceId: id, session: session)
    result(routeResult(success: attempt.success, status: attempt.status, requestedDevice: requestedDevice, actualDevice: getCurrentAudioRoute(session: session), message: attempt.message, errorCode: attempt.errorCode))
  }

  private func selectRouteByName(name: String, session: AVAudioSession, result: FlutterResult) {
    let requested = getAvailableDevices(session: session).first { ($0["name"] as? String)?.localizedCaseInsensitiveContains(name) ?? false }
    guard let requestedDevice = requested,
          let id = requestedDevice["id"] as? String else {
      result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(session: session), message: "No audio output device matched name \(name).", errorCode: nil))
      return
    }

    let attempt = applyAudioRoute(deviceId: id, session: session)
    result(routeResult(success: attempt.success, status: attempt.status, requestedDevice: requestedDevice, actualDevice: getCurrentAudioRoute(session: session), message: attempt.message, errorCode: attempt.errorCode))
  }

  private func routeToSpeaker() -> Bool {
    do {
      let session = AVAudioSession.sharedInstance()
      ensurePlayAndRecordCategory(session: session, options: [.allowBluetooth, .allowBluetoothA2DP])
      try session.overrideOutputAudioPort(.speaker)
      preferredDeviceId = "speaker"
      preferredDeviceType = "speaker"
      log("Speaker override activated. preferredDeviceType set to speaker")
      handleRouteChange(notification: Notification(name: AVAudioSession.routeChangeNotification))
      return true
    } catch {
      log("routeToSpeaker error: \(error)")
      return false
    }
  }

  private func routeToEarpiece() -> Bool {
    do {
      let session = AVAudioSession.sharedInstance()
      // Strip .allowBluetooth / .allowBluetoothA2DP so a connected BT device becomes
      // ineligible; only then will automatic routing fall back to the built-in receiver.
      // (overrideOutputAudioPort(.none) alone does nothing here because it just resumes
      // automatic routing, which still prefers BT if BT remains eligible.)
      ensurePlayAndRecordCategory(session: session, options: [])
      try session.overrideOutputAudioPort(.none)
      if let availableInputs = session.availableInputs,
         let builtInMic = availableInputs.first(where: { $0.portType == .builtInMic }) {
        try session.setPreferredInput(builtInMic)
      } else {
        try session.setPreferredInput(nil)
      }
      preferredDeviceId = "receiver"
      preferredDeviceType = "receiver"
      log("Bluetooth disallowed, speaker override cleared, preferred input cleared (earpiece default). preferredDeviceType set to receiver")
      handleRouteChange(notification: Notification(name: AVAudioSession.routeChangeNotification))
      return true
    } catch {
      log("routeToEarpiece error: \(error)")
      return false
    }
  }

  private func clearAudioRoute(session: AVAudioSession) {
    do {
      try session.overrideOutputAudioPort(.none)
      try session.setPreferredInput(nil)
    } catch {
      log("clearAudioRoute: failed to reset audio port/input: \(error.localizedDescription)")
    }
    preferredDeviceId = nil
    preferredDeviceType = nil
    handleRouteChange(notification: Notification(name: AVAudioSession.routeChangeNotification))
  }

  private func endCallSession(session: AVAudioSession) {
    clearAudioRoute(session: session)
    if shouldManageActiveState() {
      do {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
      } catch {
        log("endCallSession: failed to deactivate session: \(error.localizedDescription)")
      }
    }
  }

  private func getAvailableRoutesList(session: AVAudioSession) -> [[String: Any]] {
    // NOTE: `id` is now the stable AVAudioSession port UID string (or a fixed
    // literal for speaker/receiver) instead of Swift's randomly-seeded
    // String.hashValue. hashValue is reseeded every process launch, so the old
    // IDs were not stable across app relaunches. This is a breaking change to
    // the platform channel contract if any Dart code parses `id` as an int —
    // update the Dart model to treat `id` as a String before shipping.
    var routes: [[String: Any]] = []

    routes.append([
      "type": "speaker",
      "id": "speaker",
      "name": "Speaker"
    ])

    let showEarpiece = UIDevice.current.userInterfaceIdiom == .phone &&
      (!hasExternalDeviceConnected(session: session) || isReceiverActive(session: session))
    if showEarpiece {
      routes.append([
        "type": "earpiece",
        "id": "receiver",
        "name": "Earpiece"
      ])
    }

    if let availableInputs = session.availableInputs {
      for input in availableInputs {
        let portType = input.portType
        var type = "unknown"

        if portType == .bluetoothHFP || portType == .bluetoothLE {
          type = "bluetooth"
        } else if portType == .headsetMic || portType == .lineIn {
          type = "wired_headset"
        } else if portType == .usbAudio {
          type = "wired_headset"
        } else {
          continue
        }

        routes.append([
          "type": type,
          "id": input.uid,
          "name": input.portName
        ])
      }
    }
    return routes
  }

  private func routeResult(
    success: Bool,
    status: String,
    requestedDevice: [String: Any]?,
    actualDevice: [String: Any]?,
    message: String?,
    errorCode: String?
  ) -> [String: Any] {
    var result: [String: Any] = [
      "success": success,
      "status": status
    ]
    if let requestedDevice = requestedDevice {
      result["requestedDevice"] = requestedDevice
    }
    if let actualDevice = actualDevice {
      result["actualDevice"] = actualDevice
    }
    if let message = message {
      result["message"] = message
    }
    if let errorCode = errorCode {
      result["errorCode"] = errorCode
    }
    return result
  }

  private func shouldManageActiveState() -> Bool {
    // 1. Check if CallKit has active calls
    let callObserver = CXCallObserver()
    if !callObserver.calls.isEmpty {
      return false
    }

    // 2. Check if a WebRTC or other VoIP audio session is active
    let session = AVAudioSession.sharedInstance()
    if session.category == .playAndRecord && (session.mode == .voiceChat || session.mode == .videoChat) {
      return false
    }

    return true
  }

  // MARK: - Experimental: influence CallKit's native audio-route sheet
  //
  // UNDOCUMENTED BEHAVIOR WARNING: The native CallKit in-call audio-route
  // sheet (the system UI, not this plugin's own picker) is built and
  // populated entirely by iOS using a private heuristic over AVAudioSession
  // category options and the current active route. There is no public API to
  // filter, hide, or reorder entries in that sheet.
  //
  // Observed behavior this method targets: after overriding to Speaker while
  // Bluetooth is connected, the native sheet omits the earpiece ("iPhone")
  // row and shows only Speaker + Bluetooth. After the user then taps the
  // Bluetooth entry from that same sheet, the earpiece row reappears as an
  // option, even though category options (.allowBluetooth /
  // .allowBluetoothA2DP) have not changed between the two states.
  //
  // This method re-asserts the Bluetooth input as the explicit preferred
  // input once Bluetooth becomes the active route, WITHOUT touching category
  // options (removing .allowBluetooth/.allowBluetoothA2DP while Bluetooth is
  // active would make BT ineligible and force an immediate fallback away
  // from it, which is not the goal). This is an experiment to see whether
  // reinforcing the preferred input changes what the native sheet offers as
  // alternatives — it is not guaranteed to have any effect, and the
  // underlying heuristic may change across iOS versions or devices. Verify
  // on a real device with a real active call; this cannot be validated in a
  // simulator.
  private func reinforceBluetoothPreferredInputIfActive(session: AVAudioSession) {
    let isBluetoothActive = session.currentRoute.outputs.contains {
      $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE
    }
    guard isBluetoothActive else { return }

    guard let availableInputs = session.availableInputs,
          let btInput = availableInputs.first(where: {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
          }) else {
      return
    }

    // Avoid redundant calls if this input is already preferred.
    if session.preferredInput?.uid == btInput.uid {
      return
    }

    do {
      try session.setPreferredInput(btInput)
      log("reinforceBluetoothPreferredInputIfActive: re-asserted preferred input to \(btInput.portName)")
    } catch {
      log("reinforceBluetoothPreferredInputIfActive: failed to set preferred input: \(error.localizedDescription)")
    }
  }
}