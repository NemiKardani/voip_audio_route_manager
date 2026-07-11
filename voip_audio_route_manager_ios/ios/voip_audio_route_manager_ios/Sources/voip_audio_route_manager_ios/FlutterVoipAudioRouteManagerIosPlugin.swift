import Flutter
import UIKit
import AVFoundation
import CallKit
import os.log

@available(iOS 13.0, *)
public class FlutterVoipAudioRouteManagerIosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var channel: FlutterMethodChannel?
  private var enableLogs: Bool = false
  private var isListening = false
  private var preferredDeviceId: String?
  private var preferredDeviceType: String?
  private let callObserver = CXCallObserver()
  private var didActivateSession: Bool = false
  private var cachedDevices: [[String: Any]]?
  private var cachedDevicesTimestamp: Date?
  private var routeChangeDebounceTimer: Timer?

  private static let logger = OSLog(subsystem: "com.nemikardani.voip_audio_route_manager", category: "AudioRoute")

  private struct RouteAttempt {
    let success: Bool
    let status: String
    let message: String?
    let errorCode: String?
  }

  override init() {
    super.init()
    callObserver.setDelegate(self, queue: .main)
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

    // FIX #1: Remove CallKit delegate to prevent retain cycle
    callObserver.setDelegate(nil, queue: nil)

    // FIX #1: Deactivate audio session if we manage it
    if shouldManageActiveState() {
      let session = AVAudioSession.sharedInstance()
      do {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
      } catch {
        log("detachFromEngine: failed to deactivate session: \(error.localizedDescription)")
      }
    }

    // Clean up debounce timer
    routeChangeDebounceTimer?.invalidate()
    routeChangeDebounceTimer = nil
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
      didActivateSession = false
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

  // MARK: - Logging

  private func log(_ message: String) {
    if enableLogs {
      os_log("[VoipAudio] [iOS] %{public}@", log: Self.logger, type: .debug, message)
    }
  }

  // MARK: - CallKit Helpers

  private func isIncomingCallActiveAndNotConnected() -> Bool {
    for call in callObserver.calls {
      if !call.isOutgoing && !call.hasConnected && !call.hasEnded {
        return true
      }
    }
    return false
  }

  private func hasActiveCallKitCall() -> Bool {
    return callObserver.calls.contains { !$0.hasEnded }
  }

  // MARK: - Route String Helpers

  private func getRouteString(session: AVAudioSession) -> String {
    let currentOutput = session.currentRoute.outputs.first
    if let portType = currentOutput?.portType {
      switch portType {
      case .builtInSpeaker:   return "speaker"
      case .builtInReceiver:  return "receiver"  // FIX #8: Standardized to "receiver"
      case .bluetoothHFP,
           .bluetoothA2DP,
           .bluetoothLE:      return "bluetooth"
      case .headphones,
           .headsetMic:       return "wired_headset"
      default:                return "unknown"
      }
    }
    return "unknown"
  }

  // MARK: - Event Dispatch

  private func sendRouteAndDevicesEvents(session: AVAudioSession) {
    guard isListening else { return }
    guard let sink = eventSink else { return }

    if isIncomingCallActiveAndNotConnected() {
      log("sendRouteAndDevicesEvents: Incoming call is active but not connected. Skipping stream events.")
      return
    }

    let devices = getAvailableDevices(session: session)
    sink(["event": "devices_changed", "devices": devices])

    let routeStr = getRouteString(session: session)
    var eventData: [String: Any] = [
      "event": "route_changed",
      "route": routeStr
    ]
    if let route = getCurrentAudioRoute(session: session) {
      eventData["device"] = route
    }
    sink(eventData)
  }

  // MARK: - Notification Setup & Handling

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

  // OPTIMIZATION #2: Debounce rapid route change notifications
  @objc private func handleRouteChange(notification: Notification) {
    routeChangeDebounceTimer?.invalidate()
    routeChangeDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
      guard let self = self else { return }
      if Thread.isMainThread {
        self.handleRouteChangeOnMain(notification: notification)
      } else {
        DispatchQueue.main.async { [weak self] in
          self?.handleRouteChangeOnMain(notification: notification)
        }
      }
    }
  }

  private func handleRouteChangeOnMain(notification: Notification) {
    log("Audio route changed notification received.")
    let session = AVAudioSession.sharedInstance()
    let routeStr = getRouteString(session: session)

    // FIX #3: Consistent behavior with event stream - suppress method channel during incoming calls
    if !isIncomingCallActiveAndNotConnected() {
      channel?.invokeMethod("onAudioRouteChanged", arguments: ["route": routeStr])
    } else {
      log("handleRouteChangeOnMain: Incoming call active but not connected. Skipping method channel update.")
    }

    // FIX #5: Only reinforce for external/system changes, not programmatic ones
    if let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
       let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) {
      if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable || reason == .unknown {
        reinforceBluetoothPreferredInputIfActive(session: session)
      }
    } else {
      reinforceBluetoothPreferredInputIfActive(session: session)
    }

    // FIX #2: Sync preferred device state before sending events
    syncPreferredDeviceWithCurrentRoute(session: session)

    // Invalidate device cache on route change
    cachedDevices = nil
    cachedDevicesTimestamp = nil

    sendRouteAndDevicesEvents(session: session)
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
    if isIncomingCallActiveAndNotConnected() {
      log("handleInterruptionOnMain: Incoming call is active but not connected. Skipping stream events.")
      return
    }

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

  // MARK: - Port Type Mapping

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

  // MARK: - Device Discovery

  private func getAvailableDevices(session: AVAudioSession) -> [[String: Any]] {
    // OPTIMIZATION #1: Return cached result if available and recent
    if let cached = cachedDevices,
       let timestamp = cachedDevicesTimestamp,
       Date().timeIntervalSince(timestamp) < 0.1 {
      return cached
    }

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
    // NOTE: iOS does not expose a direct "available audio outputs" API.
    // We infer available outputs from available inputs (for headsets with mics)
    // and current route outputs (for A2DP devices that may be output-only).
    // This means output-only Bluetooth speakers may not appear until they become active.
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

        // Add if not already listed (deduplicate by id to prevent showing duplicates for same device)
        if !rawDevices.contains(where: { ($0["id"] as? String) == id }) {
          rawDevices.append([
            "id": id,
            "name": name,
            "type": type
          ])
        }
      }
    }

    // Get current active route details for isSelected calculation
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

    // Build final devices with isSelected flag
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

    // Cache result
    cachedDevices = finalDevices
    cachedDevicesTimestamp = Date()

    return finalDevices
  }

  // FIX #2: Extracted state synchronization from getAvailableDevices
  private func syncPreferredDeviceWithCurrentRoute(session: AVAudioSession) {
    let hasBluetooth = getAvailableDevices(session: session).contains {
      let t = $0["type"] as? String
      return t == "bluetooth" || t == "airpods"
    }
    let hasWired = getAvailableDevices(session: session).contains {
      let t = $0["type"] as? String
      return t == "wiredHeadset" || t == "usbAudio"
    }

    if let preferredType = preferredDeviceType {
      var isPreferredConnected = false
      if preferredType == "speaker" || preferredType == "receiver" {
        isPreferredConnected = true
      } else {
        isPreferredConnected = getAvailableDevices(session: session).contains { ($0["type"] as? String) == preferredType }
      }

      if !isPreferredConnected {
        log("Preferred device type \(preferredType) is no longer connected. Clearing preference.")
        preferredDeviceType = nil
        preferredDeviceId = nil
      }
    }

    // Infer active system route details
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

  // MARK: - Category Management

  private func ensurePlayAndRecordCategory(session: AVAudioSession, options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP]) {
    log("ensurePlayAndRecordCategory starting. Category: \(session.category.rawValue), Options: \(session.categoryOptions), requestedOptions: \(options)")

    // FIX #4: Check for truly active CallKit calls, not just any call in the array
    if hasActiveCallKitCall() {
      log("ensurePlayAndRecordCategory: Active CallKit call detected — skipping category mutation to avoid conflicting with CallKit's own AVAudioSession configuration.")
      return
    }

    if session.category != .playAndRecord || session.categoryOptions != options {
      do {
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        if shouldManageActiveState() {
          try session.setActive(true, options: .notifyOthersOnDeactivation)
          didActivateSession = true  // FIX #9: Track that we activated it
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
    didActivateSession = false
    handleRouteChange(notification: Notification(name: AVAudioSession.routeChangeNotification))
  }

  private func endCallSession(session: AVAudioSession) {
    clearAudioRoute(session: session)
    if shouldManageActiveState() {
      do {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
        didActivateSession = false
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

  // FIX #9: Track whether the plugin itself activated the session
  private func shouldManageActiveState() -> Bool {
    // 1. Check if CallKit has active calls
    if hasActiveCallKitCall() {
      return false
    }

    // 2. Only manage if we activated it ourselves, or if no one else has taken over
    if didActivateSession {
      return true
    }

    // 3. If session is not active or not in voice mode, we can manage it
    let session = AVAudioSession.sharedInstance()
    if !session.isOtherAudioPlaying && session.category != .playAndRecord {
      return true
    }

    return false
  }

  // MARK: - Experimental: influence CallKit's native audio-route sheet
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

extension FlutterVoipAudioRouteManagerIosPlugin: CXCallObserverDelegate {
  public func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
    log("callObserver:callChanged: hasConnected=\(call.hasConnected), hasEnded=\(call.hasEnded), isOutgoing=\(call.isOutgoing)")

    // When an incoming call is accepted by the user
    if !call.isOutgoing && call.hasConnected && !call.hasEnded {
      log("Incoming call accepted by user. Starting streams.")
      let session = AVAudioSession.sharedInstance()
      ensurePlayAndRecordCategory(session: session)
      sendRouteAndDevicesEvents(session: session)
    }
  }
}