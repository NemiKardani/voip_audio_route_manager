import Cocoa
import FlutterMacOS
import CoreAudio

public class FlutterVoipAudioRouteManagerMacosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var enableLogs: Bool = false
  private var isListening = false

  private struct RouteAttempt {
    let success: Bool
    let status: String
    let message: String?
    let errorCode: String?
  }
  
  private var defaultOutputAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  
  private var devicesAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "voip_audio_route_manager", binaryMessenger: registrar.messenger)
    let eventChannel = FlutterEventChannel(name: "voip_audio_route_manager/events", binaryMessenger: registrar.messenger)
    
    let instance = FlutterVoipAudioRouteManagerMacosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      if let args = call.arguments as? [String: Any],
         let enableLogs = args["enableLogs"] as? Bool {
        self.enableLogs = enableLogs
      }
      result(nil)
    case "availableDevices":
      result(getAvailableDevices())
    case "currentAudioRoute":
      result(getCurrentAudioRoute())
    case "startCallSession":
      result(nil)
    case "endCallSession":
      result(nil)
    case "setAudioRoute":
      if let args = call.arguments as? [String: Any],
         let deviceIdStr = args["id"] as? String,
         let deviceId = UInt32(deviceIdStr) {
        setDefaultOutputDevice(deviceID: deviceId, result: result)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Device ID required", details: nil))
      }
    case "setAudioRouteType":
      if let args = call.arguments as? [String: Any],
         let typeStr = args["type"] as? String {
        setRouteByType(typeStr: typeStr, result: result)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Type required", details: nil))
      }
    case "setAudioRouteByName":
      if let args = call.arguments as? [String: Any],
         let name = args["name"] as? String {
        setRouteByName(name: name, result: result)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Name required", details: nil))
      }
    case "selectAudioRoute":
      if let args = call.arguments as? [String: Any],
         let deviceIdStr = args["id"] as? String,
         let deviceId = UInt32(deviceIdStr) {
        selectAudioRoute(deviceID: deviceId, result: result)
      } else {
        result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(), message: "Device ID required", errorCode: "INVALID_ARGUMENTS"))
      }
    case "selectAudioRouteType":
      if let args = call.arguments as? [String: Any],
         let typeStr = args["type"] as? String {
        selectRouteByType(typeStr: typeStr, result: result)
      } else {
        result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(), message: "Type required", errorCode: "INVALID_ARGUMENTS"))
      }
    case "selectAudioRouteByName":
      if let args = call.arguments as? [String: Any],
         let name = args["name"] as? String {
        selectRouteByName(name: name, result: result)
      } else {
        result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(), message: "Name required", errorCode: "INVALID_ARGUMENTS"))
      }
    case "clearAudioRoute":
      result(routeResult(
        success: false,
        status: "unsupported",
        requestedDevice: nil,
        actualDevice: getCurrentAudioRoute(),
        message: "macOS output routing is system-default based; there is no app-scoped route request to clear.",
        errorCode: "UNSUPPORTED_OPERATION"
      ))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    startListeningToCoreAudio()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopListeningToCoreAudio()
    self.eventSink = nil
    return nil
  }

  private func log(_ message: String) {
    if enableLogs {
      print("[VoipAudio] [macOS] \(message)")
    }
  }

  private func getAvailableDevices() -> [[String: Any]] {
    let deviceIDs = getAllDeviceIDs()
    var devices: [[String: Any]] = []
    let defaultDeviceID = getDefaultOutputDeviceID()
    
    for deviceID in deviceIDs {
      if isOutputDevice(deviceID: deviceID) {
        let name = getDeviceName(deviceID: deviceID)
        let uid = getDeviceUID(deviceID: deviceID)
        let isSelected = deviceID == defaultDeviceID
        let type = inferDeviceType(name: name, uid: uid)
        
        devices.append([
          "id": String(deviceID),
          "name": name,
          "type": type,
          "isSelected": isSelected
        ])
      }
    }
    return devices
  }

  private func getCurrentAudioRoute() -> [String: Any]? {
    let defaultDeviceID = getDefaultOutputDeviceID()
    guard defaultDeviceID != kAudioDeviceUnknown else { return nil }
    
    let name = getDeviceName(deviceID: defaultDeviceID)
    let uid = getDeviceUID(deviceID: defaultDeviceID)
    let type = inferDeviceType(name: name, uid: uid)
    
    return [
      "id": String(defaultDeviceID),
      "name": name,
      "type": type,
      "isSelected": true
    ]
  }

  private func setDefaultOutputDevice(deviceID: AudioDeviceID, result: FlutterResult) {
    let attempt = applyDefaultOutputDevice(deviceID: deviceID)
    if attempt.success {
      result(nil)
    } else {
      result(FlutterError(code: attempt.errorCode ?? "COREAUDIO_ERROR", message: attempt.message, details: nil))
    }
  }

  private func applyDefaultOutputDevice(deviceID: AudioDeviceID) -> RouteAttempt {
    var devId = deviceID
    var propertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    
    let status = AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &propertyAddress,
      0,
      nil,
      UInt32(MemoryLayout<AudioDeviceID>.size),
      &devId
    )
    
    if status == noErr {
      log("Successfully set default output device: \(deviceID)")
      notifyDevicesChanged()
      return RouteAttempt(success: true, status: "success", message: "Default output device changed successfully.", errorCode: nil)
    } else {
      return RouteAttempt(success: false, status: "error", message: "Failed to set default output device, status: \(status)", errorCode: "COREAUDIO_ERROR")
    }
  }

  private func setRouteByType(typeStr: String, result: FlutterResult) {
    let devices = getAvailableDevices()
    if let match = devices.first(where: { ($0["type"] as? String) == typeStr }),
       let idStr = match["id"] as? String,
       let deviceId = UInt32(idStr) {
      setDefaultOutputDevice(deviceID: deviceId, result: result)
    } else {
      result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No device matching type \(typeStr)", details: nil))
    }
  }

  private func setRouteByName(name: String, result: FlutterResult) {
    let devices = getAvailableDevices()
    if let match = devices.first(where: { ($0["name"] as? String)?.localizedCaseInsensitiveContains(name) ?? false }),
       let idStr = match["id"] as? String,
       let deviceId = UInt32(idStr) {
      setDefaultOutputDevice(deviceID: deviceId, result: result)
    } else {
      result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No device matching name \(name)", details: nil))
    }
  }

  private func selectAudioRoute(deviceID: AudioDeviceID, result: FlutterResult) {
    let requested = getAvailableDevices().first { ($0["id"] as? String) == String(deviceID) }
    guard let requestedDevice = requested else {
      result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(), message: "No audio output device matched the requested ID.", errorCode: nil))
      return
    }

    let attempt = applyDefaultOutputDevice(deviceID: deviceID)
    result(routeResult(success: attempt.success, status: attempt.status, requestedDevice: requestedDevice, actualDevice: getCurrentAudioRoute(), message: attempt.message, errorCode: attempt.errorCode))
  }

  private func selectRouteByType(typeStr: String, result: FlutterResult) {
    let requested = getAvailableDevices().first { ($0["type"] as? String) == typeStr }
    guard let requestedDevice = requested,
          let idStr = requestedDevice["id"] as? String,
          let deviceID = UInt32(idStr) else {
      result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(), message: "No audio output device matched type \(typeStr).", errorCode: nil))
      return
    }

    let attempt = applyDefaultOutputDevice(deviceID: deviceID)
    result(routeResult(success: attempt.success, status: attempt.status, requestedDevice: requestedDevice, actualDevice: getCurrentAudioRoute(), message: attempt.message, errorCode: attempt.errorCode))
  }

  private func selectRouteByName(name: String, result: FlutterResult) {
    let requested = getAvailableDevices().first { ($0["name"] as? String)?.localizedCaseInsensitiveContains(name) ?? false }
    guard let requestedDevice = requested,
          let idStr = requestedDevice["id"] as? String,
          let deviceID = UInt32(idStr) else {
      result(routeResult(success: false, status: "notFound", requestedDevice: nil, actualDevice: getCurrentAudioRoute(), message: "No audio output device matched name \(name).", errorCode: nil))
      return
    }

    let attempt = applyDefaultOutputDevice(deviceID: deviceID)
    result(routeResult(success: attempt.success, status: attempt.status, requestedDevice: requestedDevice, actualDevice: getCurrentAudioRoute(), message: attempt.message, errorCode: attempt.errorCode))
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

  private func getAllDeviceIDs() -> [AudioDeviceID] {
    var propertyAddress = devicesAddress
    var dataSize: UInt32 = 0
    let sizeStatus = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
    guard sizeStatus == noErr else { return [] }
    
    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    let dataStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
    guard dataStatus == noErr else { return [] }
    
    return deviceIDs
  }

  private func getDefaultOutputDeviceID() -> AudioDeviceID {
    var defaultDeviceID: AudioDeviceID = kAudioDeviceUnknown
    var propertyAddress = defaultOutputAddress
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &propertyAddress,
      0,
      nil,
      &dataSize,
      &defaultDeviceID
    )
    
    return status == noErr ? defaultDeviceID : kAudioDeviceUnknown
  }

  private func isOutputDevice(deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: 0
    )
    
    var propsize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propsize) == noErr else { return false }
    
    let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propsize))
    defer { bufferList.deallocate() }
    
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propsize, bufferList) == noErr else { return false }
    
    let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
    return buffers.contains { $0.mNumberChannels > 0 }
  }

  private func getDeviceName(deviceID: AudioDeviceID) -> String {
    var name: CFString = "" as CFString
    var propertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceNameCFString,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize = UInt32(MemoryLayout<CFString>.size)
    
    let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
    return status == noErr ? (name as String) : "Unknown Device"
  }

  private func getDeviceUID(deviceID: AudioDeviceID) -> String {
    var uid: CFString = "" as CFString
    var propertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceUID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize = UInt32(MemoryLayout<CFString>.size)
    
    let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)
    return status == noErr ? (uid as String) : ""
  }

  private func inferDeviceType(name: String, uid: String) -> String {
    let lowerName = name.toLowerCase()
    let lowerUID = uid.toLowerCase()
    
    if lowerName.contains("speaker") || lowerName.contains("built-in output") || lowerName.contains("internal speaker") {
      return "speaker"
    } else if lowerName.contains("earpiece") || lowerName.contains("receiver") {
      return "receiver"
    } else if lowerName.contains("bluetooth") || lowerName.contains("hands-free") || lowerName.contains("buds") || lowerName.contains("pods") || lowerUID.contains("bluetooth") {
      if lowerName.contains("airpods") {
        return "airpods"
      }
      return "bluetooth"
    } else if lowerName.contains("headphone") || lowerName.contains("headset") || lowerName.contains("jack") {
      return "wiredHeadset"
    } else if lowerName.contains("usb") || lowerUID.contains("usb") {
      return "usbAudio"
    } else if lowerName.contains("hdmi") {
      return "hdmi"
    } else if lowerName.contains("car") || lowerUID.contains("carplay") {
      return "carAudio"
    }
    return "unknown"
  }

  private func startListeningToCoreAudio() {
    guard !isListening else { return }
    isListening = true
    
    let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    
    AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, coreAudioListenerBlock, selfPointer)
    AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, coreAudioListenerBlock, selfPointer)
    
    log("Started listening to CoreAudio device changes.")
  }

  private func stopListeningToCoreAudio() {
    guard isListening else { return }
    isListening = false
    
    let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    
    AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, coreAudioListenerBlock, selfPointer)
    AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, coreAudioListenerBlock, selfPointer)
    
    log("Stopped listening to CoreAudio device changes.")
  }

  fileprivate func notifyDevicesChanged() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let sink = self.eventSink else { return }
      
      let devices = self.getAvailableDevices()
      sink(["event": "devices_changed", "devices": devices])
      
      if let route = self.getCurrentAudioRoute() {
        sink(["event": "route_changed", "device": route])
      }
    }
  }
}

private let coreAudioListenerBlock: AudioObjectPropertyListenerProc = { (inObjectID, inNumberAddresses, inAddresses, inClientData) -> OSStatus in
  guard let clientData = inClientData else { return noErr }
  let plugin = Unmanaged<FlutterVoipAudioRouteManagerMacosPlugin>.fromOpaque(clientData).takeUnretainedValue()
  plugin.notifyDevicesChanged()
  return noErr
}

extension String {
  func toLowerCase() -> String {
    return self.lowercased()
  }
}
