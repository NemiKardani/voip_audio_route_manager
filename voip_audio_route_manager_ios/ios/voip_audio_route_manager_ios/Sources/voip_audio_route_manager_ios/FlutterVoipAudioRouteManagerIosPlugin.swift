import Flutter
import UIKit
import AVFoundation

public class FlutterVoipAudioRouteManagerIosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var enableLogs: Bool = false
  private var isListening = false
  private var preferredDeviceId: String?
  private var preferredDeviceType: String?
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "voip_audio_route_manager", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "voip_audio_route_manager/events", binaryMessenger: registrar.messenger())
    
    let instance = FlutterVoipAudioRouteManagerIosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)
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

  @objc private func handleRouteChange(notification: Notification) {
    log("Audio route changed notification received.")
    guard isListening, let sink = eventSink else { return }
    
    let session = AVAudioSession.sharedInstance()
    let devices = getAvailableDevices(session: session)
    sink(["event": "devices_changed", "devices": devices])
    
    if let route = getCurrentAudioRoute(session: session) {
      sink(["event": "route_changed", "device": route])
    }
  }

  @objc private func handleInterruption(notification: Notification) {
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
    
    // 2. Built-in Receiver (Earpiece) - Only available on iPhone
    if UIDevice.current.userInterfaceIdiom == .phone {
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
        
        // Add if not already listed
        if !rawDevices.contains(where: { ($0["id"] as? String) == id }) {
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
          let isBluetoothPreferredAndConnected = (preferredType == "bluetooth" || preferredType == "airpods") && hasBluetooth
          let isWiredPreferredAndConnected = (preferredType == "wiredHeadset" || preferredType == "usbAudio") && hasWired
          if !isBluetoothPreferredAndConnected && !isWiredPreferredAndConnected {
            shouldOverride = true
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
    return devices.first(where: { ($0["isSelected"] as? Bool) == true }) ?? devices.first
  }

  private func isSpeakerActive(session: AVAudioSession) -> Bool {
    return session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
  }

  private func isReceiverActive(session: AVAudioSession) -> Bool {
    return session.currentRoute.outputs.contains { $0.portType == .builtInReceiver }
  }

  private func isPortActive(session: AVAudioSession, portUID: String) -> Bool {
    return session.currentRoute.outputs.contains { $0.uid == portUID } || 
           session.currentRoute.inputs.contains { $0.uid == portUID }
  }

  private func ensurePlayAndRecordCategory(session: AVAudioSession) {
    if session.category != .playAndRecord {
      do {
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        log("AVAudioSession category set to playAndRecord with voiceChat mode.")
      } catch {
        log("Failed to set AVAudioSession category to playAndRecord: \(error.localizedDescription)")
      }
    }
  }

  private func setAudioRoute(deviceId: String, session: AVAudioSession, result: FlutterResult) {
    ensurePlayAndRecordCategory(session: session)
    do {
      if deviceId == "speaker" {
        try session.overrideOutputAudioPort(.speaker)
        preferredDeviceId = "speaker"
        preferredDeviceType = "speaker"
        log("Speaker override activated. preferredDeviceType set to speaker")
        result(nil)
      } else if deviceId == "receiver" {
        if UIDevice.current.userInterfaceIdiom != .phone {
          result(FlutterError(code: "UNSUPPORTED_DEVICE", message: "Earpiece is not supported on this device", details: nil))
          return
        }
        try session.overrideOutputAudioPort(.none)
        try session.setPreferredInput(nil)
        preferredDeviceId = "receiver"
        preferredDeviceType = "receiver"
        log("Speaker override cleared, preferred input cleared (earpiece default). preferredDeviceType set to receiver")
        result(nil)
      } else {
        // Bluetooth / Wired Headset
        if let availableInputs = session.availableInputs {
          if let match = availableInputs.first(where: { $0.uid == deviceId }) {
            try session.overrideOutputAudioPort(.none)
            try session.setPreferredInput(match)
            preferredDeviceId = deviceId
            preferredDeviceType = mapPortType(match.portType, portName: match.portName)
            log("Preferred input set: \(match.portName). preferredDeviceType set to \(preferredDeviceType ?? "nil")")
            result(nil)
            return
          }
        }
        result(FlutterError(code: "DEVICE_NOT_AVAILABLE", message: "Requested device not found in available inputs", details: nil))
      }
    } catch {
      result(FlutterError(code: "AVAUDIOSESSION_ERROR", message: "Failed to switch audio route: \(error.localizedDescription)", details: nil))
    }
  }

  private func setRouteByType(typeStr: String, session: AVAudioSession, result: FlutterResult) {
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
}
