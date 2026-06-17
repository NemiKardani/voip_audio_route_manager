package com.example.voip_audio_route_manager_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.AudioDeviceCallback
import android.media.AudioFocusRequest
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

public class FlutterVoipAudioRouteManagerAndroidPlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
  private lateinit var methodChannel : MethodChannel
  private lateinit var eventChannel : EventChannel
  private var eventSink: EventChannel.EventSink? = null
  
  private var context: Context? = null
  private var audioManager: AudioManager? = null
  private var enableLogs = false
  private val handler = Handler(Looper.getMainLooper())
  
  private var audioDeviceCallback: Any? = null // Typed as Any to compile cleanly on older SDKs
  private var bluetoothReceiver: BroadcastReceiver? = null
  private var headsetReceiver: BroadcastReceiver? = null
  private var communicationDeviceListener: Any? = null
  private var focusRequest: AudioFocusRequest? = null
  private var preferredDeviceType: String? = null

  private data class RouteAttempt(
    val success: Boolean,
    val status: String,
    val message: String? = null,
    val errorCode: String? = null
  )

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    
    methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "voip_audio_route_manager")
    methodChannel.setMethodCallHandler(this)
    
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "voip_audio_route_manager/events")
    eventChannel.setStreamHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    val am = audioManager ?: return result.error("NO_AUDIO_MANAGER", "AudioManager is not initialized", null)
    
    when (call.method) {
      "initialize" -> {
        enableLogs = call.argument<Boolean>("enableLogs") ?: false
        setupAudioDeviceCallback()
        setupBroadcastReceivers()
        log("Initialized plugin with log status: $enableLogs")
        result.success(null)
      }
      "availableDevices" -> {
        result.success(getAvailableDevices(am))
      }
      "currentAudioRoute" -> {
        result.success(getCurrentAudioRoute(am))
      }
      "startCallSession" -> {
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        requestAudioFocus()
        notifyDevicesChanged()
        result.success(null)
      }
      "endCallSession" -> {
        endCallSession(am)
        result.success(null)
      }
      "setAudioRoute" -> {
        val deviceId = call.argument<String>("id")
        if (deviceId != null) {
          setAudioRouteById(am, deviceId, result)
        } else {
          result.error("INVALID_ARGUMENTS", "Device ID is required", null)
        }
      }
      "setAudioRouteType" -> {
        val type = call.argument<String>("type")
        if (type != null) {
          setRouteByType(am, type, result)
        } else {
          result.error("INVALID_ARGUMENTS", "Device type is required", null)
        }
      }
      "setAudioRouteByName" -> {
        val name = call.argument<String>("name")
        if (name != null) {
          setRouteByName(am, name, result)
        } else {
          result.error("INVALID_ARGUMENTS", "Device name is required", null)
        }
      }
      "selectAudioRoute" -> {
        val deviceId = call.argument<String>("id")
        if (deviceId != null) {
          selectAudioRouteById(am, deviceId, result)
        } else {
          result.success(routeResult(false, "notFound", null, getCurrentAudioRoute(am), "Device ID is required", "INVALID_ARGUMENTS"))
        }
      }
      "selectAudioRouteType" -> {
        val type = call.argument<String>("type")
        if (type != null) {
          selectAudioRouteByType(am, type, result)
        } else {
          result.success(routeResult(false, "notFound", null, getCurrentAudioRoute(am), "Device type is required", "INVALID_ARGUMENTS"))
        }
      }
      "selectAudioRouteByName" -> {
        val name = call.argument<String>("name")
        if (name != null) {
          selectAudioRouteByName(am, name, result)
        } else {
          result.success(routeResult(false, "notFound", null, getCurrentAudioRoute(am), "Device name is required", "INVALID_ARGUMENTS"))
        }
      }
      "clearAudioRoute" -> {
        clearAudioRoute(am)
        result.success(null)
      }
      "switchToSpeaker" -> {
        result.success(routeToSpeaker(am))
      }
      "switchToEarpiece" -> {
        result.success(routeToEarpiece(am))
      }
      "getAvailableRoutes" -> {
        val routes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
          am.availableCommunicationDevices.map { device ->
            mapOf(
              "type" to when (device.type) {
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER  -> "speaker"
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO    -> "bluetooth"
                AudioDeviceInfo.TYPE_BLE_HEADSET      -> "bluetooth"
                AudioDeviceInfo.TYPE_WIRED_HEADSET    -> "wired_headset"
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired_headset"
                else -> "unknown"
              },
              "id"   to device.id,
              "name" to (device.productName?.toString() ?: "Unknown")
            )
          }
        } else {
          listOf(
            mapOf("type" to "speaker", "id" to 1, "name" to "Built-in Speaker"),
            mapOf("type" to "earpiece", "id" to 2, "name" to "Built-in Earpiece")
          )
        }
        result.success(routes)
      }
      "getCurrentRoute" -> {
        val current = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
          am.communicationDevice?.type
        } else null
        result.success(current?.toString())
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
    requestAudioFocus()
    log("Event channel stream listening started.")
  }

  override fun onCancel(arguments: Any?) {
    abandonAudioFocus()
    eventSink = null
    log("Event channel stream listening stopped.")
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    teardownCallbacks()
    context = null
    audioManager = null
  }

  private fun log(message: String) {
    if (enableLogs) {
      android.util.Log.d("VoipAudioAndroid", message)
    }
  }

  private fun setupAudioDeviceCallback() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
          log("Audio devices added.")
          notifyDevicesChanged()
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
          log("Audio devices removed.")
          notifyDevicesChanged()
        }
      }
      audioManager?.registerAudioDeviceCallback(callback, handler)
      audioDeviceCallback = callback
    }
    
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && audioManager != null) {
      val listener = AudioManager.OnCommunicationDeviceChangedListener { device ->
        log("Communication device changed to: ${device?.productName}")
        notifyDevicesChanged()
      }
      audioManager?.addOnCommunicationDeviceChangedListener(context?.mainExecutor!!, listener)
      communicationDeviceListener = listener
    }
  }

  private fun setupBroadcastReceivers() {
    val ctx = context ?: return
    
    // Listen to Bluetooth SCO changes
    bluetoothReceiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED) {
          val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, -1)
          log("Bluetooth SCO audio state updated: $state")
          notifyDevicesChanged()
        }
      }
    }
    ctx.registerReceiver(bluetoothReceiver, IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED))

    // Listen to Wired Headset plug
    headsetReceiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == Intent.ACTION_HEADSET_PLUG) {
          val state = intent.getIntExtra("state", -1)
          log("Wired Headset plug state updated: $state")
          notifyDevicesChanged()
        }
      }
    }
    ctx.registerReceiver(headsetReceiver, IntentFilter(Intent.ACTION_HEADSET_PLUG))
  }

  private fun teardownCallbacks() {
    val ctx = context
    val am = audioManager
    
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && am != null && audioDeviceCallback != null) {
      am.unregisterAudioDeviceCallback(audioDeviceCallback as AudioDeviceCallback)
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && am != null && communicationDeviceListener != null) {
      am.removeOnCommunicationDeviceChangedListener(communicationDeviceListener as AudioManager.OnCommunicationDeviceChangedListener)
    }
    if (ctx != null) {
      bluetoothReceiver?.let { ctx.unregisterReceiver(it) }
      headsetReceiver?.let { ctx.unregisterReceiver(it) }
    }
    bluetoothReceiver = null
    headsetReceiver = null
    audioDeviceCallback = null
    communicationDeviceListener = null
  }

  private fun notifyDevicesChanged() {
    val am = audioManager ?: return
    val current = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      when (am.communicationDevice?.type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLE_HEADSET -> "bluetooth"
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired_headset"
        null -> "none"
        else -> "unknown"
      }
    } else {
      @Suppress("DEPRECATION")
      if (am.isSpeakerphoneOn) "speaker" else "earpiece"
    }

    handler.post {
      methodChannel.invokeMethod("onAudioRouteChanged", mapOf("route" to current))
      
      val sink = eventSink ?: return@post
      val devices = getAvailableDevices(am)
      sink.success(mapOf("event" to "devices_changed", "devices" to devices))
      
      val route = getCurrentAudioRoute(am)
      sink.success(mapOf(
        "event" to "route_changed",
        "route" to current,
        "device" to (route ?: mapOf("id" to current, "name" to current, "type" to current, "isSelected" to true))
      ))
    }
  }

  private fun getAvailableDevices(am: AudioManager): List<Map<String, Any>> {
    val list = mutableListOf<Map<String, Any>>()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      val infoList = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
      
      // Check if we have any advanced Bluetooth device (A2DP or BLE)
      val hasAdvancedBluetooth = infoList.any { 
        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || 
        it.type == AudioDeviceInfo.TYPE_BLE_HEADSET 
      }
      
      val currentDevice = getActiveCommunicationDevice(am)
      val currentDeviceType = currentDevice?.type
      
      val rawDevices = mutableListOf<Map<String, Any>>()
      for (info in infoList) {
        log("AudioDeviceInfo: id=${info.id}, name=${info.productName}, nativeType=${info.type}, mappedType=${mapDeviceType(info.type)}")
        // Skip TYPE_BLUETOOTH_SCO if we already have A2DP or BLE headset to avoid duplicates
        if (hasAdvancedBluetooth && info.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
          continue
        }
        
        val type = mapDeviceType(info.type)
        if (type == "unknown") continue
        
        rawDevices.add(mapOf(
          "id" to info.id.toString(),
          "name" to info.productName.toString(),
          "type" to type,
          "nativeType" to info.type
        ))
      }
      
      val hasBluetooth = rawDevices.any { it["type"] == "bluetooth" || it["type"] == "airpods" }
      val hasWired = rawDevices.any { it["type"] == "wiredHeadset" || it["type"] == "usbAudio" }
      
      // Update preferredDeviceType based on current state and connectivity
      if (preferredDeviceType != null) {
        val isPreferredTypeConnected = when (preferredDeviceType) {
          "speaker" -> rawDevices.any { it["type"] == "speaker" }
          "receiver" -> rawDevices.any { it["type"] == "receiver" }
          "bluetooth", "airpods" -> hasBluetooth
          "wiredHeadset", "usbAudio" -> hasWired
          else -> false
        }
        
        if (!isPreferredTypeConnected) {
          log("Preferred device type $preferredDeviceType is no longer connected. Clearing preference.")
          preferredDeviceType = null
        }
      }
      
      // If preferredDeviceType is null, let's see if we should infer it from the current active device
      if (preferredDeviceType == null && currentDevice != null) {
        val activeType = mapDeviceType(currentDeviceType ?: -1)
        if (activeType != "unknown") {
          preferredDeviceType = activeType
          log("Inferred preferredDeviceType from active device: $preferredDeviceType")
        }
      } else if (preferredDeviceType != null && currentDevice != null) {
        val currentMappedType = mapDeviceType(currentDeviceType ?: -1)
        if (currentMappedType != "unknown") {
          var shouldOverride = false
          if (preferredDeviceType != currentMappedType) {
            if (currentMappedType == "wiredHeadset" || currentMappedType == "usbAudio") {
              shouldOverride = true
            } else if (currentMappedType == "bluetooth" || currentMappedType == "airpods") {
              shouldOverride = true
            } else if (currentMappedType == "speaker" || currentMappedType == "receiver") {
              val isBluetoothPreferredAndConnected = (preferredDeviceType == "bluetooth" || preferredDeviceType == "airpods") && hasBluetooth
              val isWiredPreferredAndConnected = (preferredDeviceType == "wiredHeadset" || preferredDeviceType == "usbAudio") && hasWired
              if (!isBluetoothPreferredAndConnected && !isWiredPreferredAndConnected) {
                shouldOverride = true
              }
            }
          }
          if (shouldOverride) {
            log("System routed to $currentMappedType overriding preference $preferredDeviceType")
            preferredDeviceType = currentMappedType
          }
        }
      }
      
      for (device in rawDevices) {
        val devId = device["id"] as String
        val devType = device["type"] as String
        val devNativeType = device["nativeType"] as Int
        
        val isSelected = if (preferredDeviceType != null) {
          if (preferredDeviceType == "bluetooth" || preferredDeviceType == "airpods") {
            devType == "bluetooth" || devType == "airpods"
          } else if (preferredDeviceType == "wiredHeadset" || preferredDeviceType == "usbAudio") {
            devType == "wiredHeadset" || devType == "usbAudio"
          } else {
            devType == preferredDeviceType
          }
        } else {
          if (currentDevice != null) {
            if (currentDeviceType == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || 
                currentDeviceType == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || 
                currentDeviceType == AudioDeviceInfo.TYPE_BLE_HEADSET) {
              devType == "bluetooth" || devType == "airpods"
            } else {
              devId == currentDevice.id.toString()
            }
          } else {
            // Fallback guess based on system routing hierarchy
            if (am.isSpeakerphoneOn) {
              devType == "speaker"
            } else if (hasBluetooth) {
              devType == "bluetooth" || devType == "airpods"
            } else if (hasWired) {
              devType == "wiredHeadset" || devType == "usbAudio"
            } else {
              devType == "receiver"
            }
          }
        }
        
        list.add(mapOf(
          "id" to devId,
          "name" to device["name"] as String,
          "type" to devType,
          "isSelected" to isSelected
        ))
      }
    } else {
      // Legacy basic devices list
      val isSpeaker = am.isSpeakerphoneOn
      val isBluetooth = am.isBluetoothScoOn
      
      list.add(mapOf("id" to "speaker", "name" to "Built-in Speaker", "type" to "speaker", "isSelected" to isSpeaker))
      list.add(mapOf("id" to "receiver", "name" to "Built-in Earpiece", "type" to "receiver", "isSelected" to (!isSpeaker && !isBluetooth)))
      if (isBluetooth) {
        list.add(mapOf("id" to "bluetooth", "name" to "Bluetooth Device", "type" to "bluetooth", "isSelected" to true))
      }
    }
    return list
  }

  private fun getCurrentAudioRoute(am: AudioManager): Map<String, Any>? {
    val devices = getAvailableDevices(am)
    return devices.firstOrNull { it["isSelected"] == true } ?: devices.firstOrNull()
  }

  private fun getActiveCommunicationDevice(am: AudioManager): AudioDeviceInfo? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      return am.communicationDevice
    }
    return null
  }

  private fun setAudioRouteById(am: AudioManager, id: String, result: Result) {
    val attempt = applyAudioRouteById(am, id)
    if (attempt.success) {
      result.success(null)
    } else {
      result.error(attempt.errorCode ?: "ROUTING_FAILED", attempt.message ?: "Failed to switch audio route", null)
    }
  }

  private fun applyAudioRouteById(am: AudioManager, id: String): RouteAttempt {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val infoList = am.availableCommunicationDevices
      val targetId = id.toIntOrNull()

      var targetDevice = infoList.firstOrNull { it.id == targetId }
      if (targetDevice == null && targetId != null) {
        // If ID match fails, try matching by TYPE (e.g. if A2DP ID was passed but SCO ID is in availableCommunicationDevices)
        val allDevices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val selectedDevice = allDevices.firstOrNull { it.id == targetId }
        if (selectedDevice != null) {
          val selectedType = mapDeviceType(selectedDevice.type)
          targetDevice = infoList.firstOrNull { mapDeviceType(it.type) == selectedType }
        }
      }

      if (targetDevice != null) {
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        val success = am.setCommunicationDevice(targetDevice)
        if (success) {
          preferredDeviceType = mapDeviceType(targetDevice.type)
          log("Successfully set communication device to: ${targetDevice.productName}, preferredDeviceType set to: $preferredDeviceType")
          notifyDevicesChanged()
          return RouteAttempt(true, "success", "Audio route changed successfully.")
        } else {
          return RouteAttempt(false, "rejected", "Android rejected communication routing request", "ROUTING_REJECTED")
        }
      } else {
        // ID could be speaker/receiver if legacy fallback maps it
        return fallbackRouting(am, id)
      }
    } else {
      return fallbackRouting(am, id)
    }
  }

  private fun fallbackRouting(am: AudioManager, deviceTypeOrId: String): RouteAttempt {
    am.mode = AudioManager.MODE_IN_COMMUNICATION
    try {
      val normalized = deviceTypeOrId.lowercase()
      if (normalized.contains("speaker")) {
        am.isSpeakerphoneOn = true
        am.stopBluetoothSco()
        am.isBluetoothScoOn = false
        preferredDeviceType = "speaker"
        log("Fallback: speakerphone enabled. preferredDeviceType set to: speaker")
      } else if (normalized.contains("receiver") || normalized.contains("earpiece")) {
        am.isSpeakerphoneOn = false
        am.stopBluetoothSco()
        am.isBluetoothScoOn = false
        preferredDeviceType = "receiver"
        log("Fallback: receiver enabled. preferredDeviceType set to: receiver")
      } else if (normalized.contains("bluetooth") || normalized.contains("airpods")) {
        am.isSpeakerphoneOn = false
        am.startBluetoothSco()
        am.isBluetoothScoOn = true
        preferredDeviceType = "bluetooth"
        log("Fallback: bluetooth SCO enabled. preferredDeviceType set to: bluetooth")
      } else {
        am.isSpeakerphoneOn = false
        am.stopBluetoothSco()
        am.isBluetoothScoOn = false
        preferredDeviceType = null
        log("Fallback: default route. preferredDeviceType cleared.")
      }
      notifyDevicesChanged()
      return RouteAttempt(true, "success", "Legacy audio route change requested.")
    } catch (e: Exception) {
      return RouteAttempt(false, "error", "Failed legacy audio route change: ${e.message}", "FALLBACK_ROUTE_ERROR")
    }
  }

  private fun setRouteByType(am: AudioManager, type: String, result: Result) {
    val attempt = applyRouteByType(am, type)
    if (attempt.success) {
      result.success(null)
    } else {
      result.error(attempt.errorCode ?: "ROUTING_FAILED", attempt.message ?: "Failed to switch audio route", null)
    }
  }

  private fun applyRouteByType(am: AudioManager, type: String): RouteAttempt {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val infoList = am.availableCommunicationDevices
      val targetDevice = infoList.firstOrNull { mapDeviceType(it.type) == type }

      if (targetDevice != null) {
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        val success = am.setCommunicationDevice(targetDevice)
        if (success) {
          preferredDeviceType = type
          log("Successfully set communication device by type $type, preferredDeviceType set to: $preferredDeviceType")
          notifyDevicesChanged()
          return RouteAttempt(true, "success", "Audio route changed successfully.")
        }
        return RouteAttempt(false, "rejected", "Android rejected communication routing request", "ROUTING_REJECTED")
      }
    }
    return fallbackRouting(am, type)
  }

  private fun setRouteByName(am: AudioManager, name: String, result: Result) {
    val attempt = applyRouteByName(am, name)
    if (attempt.success) {
      result.success(null)
    } else {
      result.error(attempt.errorCode ?: "ROUTING_FAILED", attempt.message ?: "Failed to switch audio route", null)
    }
  }

  private fun applyRouteByName(am: AudioManager, name: String): RouteAttempt {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val infoList = am.availableCommunicationDevices
      val targetDevice = infoList.firstOrNull { it.productName.toString().contains(name, ignoreCase = true) }

      if (targetDevice != null) {
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        val success = am.setCommunicationDevice(targetDevice)
        if (success) {
          preferredDeviceType = mapDeviceType(targetDevice.type)
          log("Successfully set communication device by name $name, preferredDeviceType set to: $preferredDeviceType")
          notifyDevicesChanged()
          return RouteAttempt(true, "success", "Audio route changed successfully.")
        }
        return RouteAttempt(false, "rejected", "Android rejected communication routing request", "ROUTING_REJECTED")
      }
    }
    return fallbackRouting(am, name)
  }

  private fun selectAudioRouteById(am: AudioManager, id: String, result: Result) {
    val requested = getAvailableDevices(am).firstOrNull { it["id"] == id }
    if (requested == null) {
      result.success(routeResult(false, "notFound", null, getCurrentAudioRoute(am), "No audio output device matched the requested ID.", null))
      return
    }

    val attempt = applyAudioRouteById(am, id)
    result.success(routeResult(attempt.success, attempt.status, requested, getCurrentAudioRoute(am), attempt.message, attempt.errorCode))
  }

  private fun selectAudioRouteByType(am: AudioManager, type: String, result: Result) {
    val requested = getAvailableDevices(am).firstOrNull { it["type"] == type }
    if (requested == null) {
      result.success(routeResult(false, "notFound", null, getCurrentAudioRoute(am), "No audio output device matched type $type.", null))
      return
    }

    val attempt = applyRouteByType(am, type)
    result.success(routeResult(attempt.success, attempt.status, requested, getCurrentAudioRoute(am), attempt.message, attempt.errorCode))
  }

  private fun selectAudioRouteByName(am: AudioManager, name: String, result: Result) {
    val requested = getAvailableDevices(am).firstOrNull {
      (it["name"] as? String)?.contains(name, ignoreCase = true) == true
    }
    if (requested == null) {
      result.success(routeResult(false, "notFound", null, getCurrentAudioRoute(am), "No audio output device matched name $name.", null))
      return
    }

    val attempt = applyRouteByName(am, name)
    result.success(routeResult(attempt.success, attempt.status, requested, getCurrentAudioRoute(am), attempt.message, attempt.errorCode))
  }

  private fun ensureCommunicationMode(am: AudioManager) {
    am.mode = AudioManager.MODE_IN_COMMUNICATION

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      if (focusRequest == null) {
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
          .setAudioAttributes(
            AudioAttributes.Builder()
              .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
              .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
              .build()
          )
          .setAcceptsDelayedFocusGain(false)
          .build()
        focusRequest = request
      }
      focusRequest?.let { am.requestAudioFocus(it) }
    } else {
      @Suppress("DEPRECATION")
      am.requestAudioFocus(null, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
    }
  }

  private fun routeToSpeaker(am: AudioManager): Boolean {
    ensureCommunicationMode(am)

    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val speaker = am.availableCommunicationDevices
        .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
      if (speaker != null) {
        val success = am.setCommunicationDevice(speaker)
        if (success) {
          preferredDeviceType = "speaker"
          notifyDevicesChanged()
        }
        success
      } else {
        false
      }
    } else {
      @Suppress("DEPRECATION")
      am.isSpeakerphoneOn = true
      @Suppress("DEPRECATION")
      am.isBluetoothScoOn = false
      am.stopBluetoothSco()
      preferredDeviceType = "speaker"
      notifyDevicesChanged()
      true
    }
  }

  private fun routeToEarpiece(am: AudioManager): Boolean {
    ensureCommunicationMode(am)

    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val earpiece = am.availableCommunicationDevices
        .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
      if (earpiece != null) {
        val success = am.setCommunicationDevice(earpiece)
        if (success) {
          preferredDeviceType = "receiver"
          notifyDevicesChanged()
        }
        success
      } else {
        val success = am.clearCommunicationDevice()
        preferredDeviceType = "receiver"
        notifyDevicesChanged()
        true
      }
    } else {
      @Suppress("DEPRECATION")
      am.isSpeakerphoneOn = false
      @Suppress("DEPRECATION")
      am.isBluetoothScoOn = false
      am.stopBluetoothSco()
      preferredDeviceType = "receiver"
      notifyDevicesChanged()
      true
    }
  }

  private fun clearAudioRoute(am: AudioManager) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      am.clearCommunicationDevice()
    } else {
      @Suppress("DEPRECATION")
      am.isSpeakerphoneOn = false
      @Suppress("DEPRECATION")
      am.isBluetoothScoOn = false
      am.stopBluetoothSco()
    }
    preferredDeviceType = null
    am.mode = AudioManager.MODE_NORMAL
    notifyDevicesChanged()
  }

  private fun endCallSession(am: AudioManager) {
    clearAudioRoute(am)
    abandonAudioFocus()
    am.mode = AudioManager.MODE_NORMAL
  }

  private fun routeResult(
    success: Boolean,
    status: String,
    requestedDevice: Map<String, Any>?,
    actualDevice: Map<String, Any>?,
    message: String?,
    errorCode: String?
  ): Map<String, Any?> {
    return mapOf(
      "success" to success,
      "status" to status,
      "requestedDevice" to requestedDevice,
      "actualDevice" to actualDevice,
      "message" to message,
      "errorCode" to errorCode
    )
  }

  private fun requestAudioFocus() {
    val am = audioManager ?: return
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val focusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
          handleAudioFocusChange(focusChange)
        }
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
          .setAudioAttributes(
            AudioAttributes.Builder()
              .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
              .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
              .build()
          )
          .setOnAudioFocusChangeListener(focusListener, handler)
          .build()
        
        am.requestAudioFocus(request)
        focusRequest = request
      } else {
        @Suppress("DEPRECATION")
        am.requestAudioFocus(
          { focusChange -> handleAudioFocusChange(focusChange) },
          AudioManager.STREAM_VOICE_CALL,
          AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
        )
      }
      log("Requested Audio Focus.")
    } catch (e: Exception) {
      log("Error requesting Audio Focus: ${e.message}")
    }
  }

  private fun abandonAudioFocus() {
    val am = audioManager ?: return
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        focusRequest?.let { am.abandonAudioFocusRequest(it) }
      } else {
        @Suppress("DEPRECATION")
        am.abandonAudioFocus { }
      }
      log("Abandoned Audio Focus.")
    } catch (e: Exception) {
      log("Error abandoning Audio Focus: ${e.message}")
    }
  }

  private fun handleAudioFocusChange(focusChange: Int) {
    val sink = eventSink ?: return
    val focused = focusChange == AudioManager.AUDIOFOCUS_GAIN
    log("Audio focus change listener: $focusChange (focused=$focused)")
    sink.success(mapOf("event" to "audio_focus_changed", "focused" to focused))
  }

  private fun mapDeviceType(nativeType: Int): String {
    return when (nativeType) {
      AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
      AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "receiver"
      AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
      AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
      AudioDeviceInfo.TYPE_BLE_HEADSET -> "bluetooth"
      AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wiredHeadset"
      AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wiredHeadset"
      AudioDeviceInfo.TYPE_USB_DEVICE -> "usbAudio"
      AudioDeviceInfo.TYPE_USB_ACCESSORY -> "usbAudio"
      AudioDeviceInfo.TYPE_USB_HEADSET -> "usbAudio"
      AudioDeviceInfo.TYPE_HDMI -> "hdmi"
      AudioDeviceInfo.TYPE_HDMI_ARC -> "hdmi"
      AudioDeviceInfo.TYPE_LINE_ANALOG -> "wiredHeadset"
      else -> "unknown"
    }
  }
}
