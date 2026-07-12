package expo.modules.speechtotext

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.speech.RecognizerIntent
import expo.modules.interfaces.permissions.PermissionsResponseListener
import expo.modules.interfaces.permissions.PermissionsStatus
import expo.modules.kotlin.functions.Coroutine
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

class ExpoSpeechToTextModule : Module() {
  private val availabilityEvent = "onAvailabilityChange"
  private val listeningEvent = "onListeningStateChange"
  private val readyEvent = "onReadyStateChange"
  private val stoppingEvent = "onStoppingStateChange"
  private val transcriptEvent = "onTranscript"
  private val errorEvent = "onError"

  private var hasObservers = false

  private val controller by lazy {
    SpeechToTextController(
      context = requireNotNull(appContext.reactContext),
      onAvailabilityChanged = { available ->
        if (hasObservers) {
          sendEvent(availabilityEvent, mapOf("available" to available))
        }
      },
      onListeningChanged = { listening ->
        if (hasObservers) {
          sendEvent(listeningEvent, mapOf("listening" to listening))
        }
      },
      onReadyChanged = { ready ->
        if (hasObservers) {
          sendEvent(readyEvent, mapOf("ready" to ready))
        }
      },
      onStoppingChanged = { stopping ->
        if (hasObservers) {
          sendEvent(stoppingEvent, mapOf("stopping" to stopping))
        }
      },
      onTranscript = {
          transcript,
          rawTranscript,
          cleanedTranscript,
          cleanupStatus,
          engine,
          segments,
          isFinal ->
        if (hasObservers) {
          sendEvent(
            transcriptEvent,
            mapOf(
              "transcript" to transcript,
              "rawTranscript" to rawTranscript,
              "cleanedTranscript" to cleanedTranscript,
              "cleanupStatus" to cleanupStatus.rawValue,
              "engine" to engine,
              "segments" to segments.map { it.toMap() },
              "isFinal" to isFinal
            )
          )
        }
      },
      onError = { error ->
        if (hasObservers) {
          sendEvent(
            errorEvent,
            mapOf(
              "code" to error.code,
              "message" to error.message
            )
          )
        }
      }
    )
  }

  override fun definition() = ModuleDefinition {
    Name("ExpoSpeechToText")

    Events(
      availabilityEvent,
      listeningEvent,
      readyEvent,
      stoppingEvent,
      transcriptEvent,
      errorEvent
    )

    OnStartObserving {
      hasObservers = true
    }

    OnStopObserving {
      hasObservers = false
    }

    OnDestroy {
      controller.invalidate()
    }

    AsyncFunction("getStateAsync") Coroutine { ->
      val permissionSnapshot = getPermissionSnapshot()
      withContext(Dispatchers.Main) {
        controller.getState() + mapOf(
          "permissionStatus" to permissionSnapshot.toSpeechToTextPermissionStatus(),
          "lastError" to null
        )
      }
    }

    AsyncFunction("getPermissionStatusAsync") Coroutine { ->
      getPermissionSnapshot().toSpeechToTextPermissionStatus()
    }

    AsyncFunction("getCapabilitiesAsync") Coroutine { ->
      val context = requireNotNull(appContext.reactContext)
      val controllerState = withContext(Dispatchers.Main) { controller.getState() }
      val locale = controllerState["capabilities"]
        ?.let { it as? Map<*, *> }
        ?.get("supportedLocale") as? String ?: "en-US"
      SpeechToTextOnDeviceAi(context).getCapabilities(locale).toMap()
    }

    AsyncFunction("prepareOnDeviceModelsAsync") Coroutine { options: Map<String, Any?> ->
      val context = requireNotNull(appContext.reactContext)
      val locale = SpeechToTextStartOptions.fromMap(options).locale
      SpeechToTextOnDeviceAi(context).prepareModels(locale).toMap()
    }

    AsyncFunction("getSupportedLocalesAsync") Coroutine { ->
      getSupportedLocales()
    }

    AsyncFunction("requestPermissionsAsync") Coroutine { ->
      requestMicrophonePermission()
    }

    AsyncFunction("startListening") Coroutine { options: Map<String, Any?> ->
      ensureMicrophonePermissionGranted()
      withContext(Dispatchers.Main) {
        controller.startListening(SpeechToTextStartOptions.fromMap(options))
      }
    }

    AsyncFunction("stopListening") Coroutine { ->
      withContext(Dispatchers.Main) {
        controller.stopListening()
      }
    }

    Function("resetTranscript") {
      controller.resetTranscript()
    }
  }

  private suspend fun ensureMicrophonePermissionGranted() {
    val permissionsManager = appContext.permissions
      ?: throw SpeechToTextModuleException(
        SpeechToTextErrorCodes.UNKNOWN,
        "Permissions module is not available"
      )

    val currentPermission = getPermissionSnapshot(permissionsManager)
    if (currentPermission.status == PermissionsStatus.GRANTED) {
      return
    }

    if (currentPermission.status == PermissionsStatus.DENIED && !currentPermission.canAskAgain) {
      throw SpeechToTextModuleException(
        SpeechToTextErrorCodes.PERMISSION_RESTRICTED,
        "Speech recognition permission is restricted on this device"
      )
    }

    throw SpeechToTextModuleException(
      if (currentPermission.status == PermissionsStatus.UNDETERMINED) {
        SpeechToTextErrorCodes.PERMISSION_NOT_DETERMINED
      } else {
        SpeechToTextErrorCodes.PERMISSION_DENIED
      },
      if (currentPermission.status == PermissionsStatus.UNDETERMINED) {
        "Speech recognition permission was not yet determined"
      } else {
        "Speech recognition permission was denied"
      }
    )
  }

  private suspend fun requestMicrophonePermission(): String {
    val permissionsManager = appContext.permissions
      ?: throw SpeechToTextModuleException(
        SpeechToTextErrorCodes.UNKNOWN,
        "Permissions module is not available"
      )

    val currentPermission = getPermissionSnapshot(permissionsManager)
    when (currentPermission.toSpeechToTextPermissionStatus()) {
      "granted",
      "denied",
      "restricted" -> return currentPermission.toSpeechToTextPermissionStatus()
    }

    return requestPermissionSnapshot(permissionsManager).toSpeechToTextPermissionStatus()
  }

  private suspend fun getPermissionSnapshot(): PermissionSnapshot {
    val permissionsManager = appContext.permissions
      ?: throw SpeechToTextModuleException(
        SpeechToTextErrorCodes.UNKNOWN,
        "Permissions module is not available"
      )

    return getPermissionSnapshot(permissionsManager)
  }

  private suspend fun getPermissionSnapshot(
    permissionsManager: expo.modules.interfaces.permissions.Permissions
  ): PermissionSnapshot = suspendCancellableCoroutine { continuation ->
    permissionsManager.getPermissions(
      PermissionsResponseListener { permissionsMap ->
        val response = permissionsMap[Manifest.permission.RECORD_AUDIO]
        continuation.resume(
          PermissionSnapshot(
            status = response?.status ?: PermissionsStatus.UNDETERMINED,
            canAskAgain = response?.canAskAgain ?: true
          )
        )
      },
      Manifest.permission.RECORD_AUDIO
    )
  }

  private suspend fun requestPermissionSnapshot(
    permissionsManager: expo.modules.interfaces.permissions.Permissions
  ): PermissionSnapshot = suspendCancellableCoroutine { continuation ->
    permissionsManager.askForPermissions(
      PermissionsResponseListener { permissionsMap ->
        val response = permissionsMap[Manifest.permission.RECORD_AUDIO]
        continuation.resume(
          PermissionSnapshot(
            status = response?.status ?: PermissionsStatus.UNDETERMINED,
            canAskAgain = response?.canAskAgain ?: true
          )
        )
      },
      Manifest.permission.RECORD_AUDIO
    )
  }

  private suspend fun getSupportedLocales(): List<String> =
    suspendCancellableCoroutine { continuation ->
      val context = appContext.reactContext
      if (context == null) {
        continuation.resume(emptyList())
        return@suspendCancellableCoroutine
      }

      val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
          val extras = getResultExtras(true)
          val supportedLanguages =
            extras?.getStringArrayList(RecognizerIntent.EXTRA_SUPPORTED_LANGUAGES).orEmpty()
          val preferredLanguage = extras?.getString(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE)

          continuation.resume(
            (supportedLanguages + listOfNotNull(preferredLanguage))
              .map { languageTag -> languageTag.trim().replace('_', '-') }
              .filter { languageTag -> languageTag.isNotEmpty() }
              .distinct()
              .sorted()
          )
        }
      }

      try {
        context.sendOrderedBroadcast(
          Intent(RecognizerIntent.ACTION_GET_LANGUAGE_DETAILS),
          null,
          receiver,
          null,
          Activity.RESULT_OK,
          null,
          null
        )
      } catch (_: Exception) {
        continuation.resume(emptyList())
      }
    }
}

private data class PermissionSnapshot(
  val status: PermissionsStatus,
  val canAskAgain: Boolean
)

private fun PermissionSnapshot.toSpeechToTextPermissionStatus(): String {
  return when (status) {
    PermissionsStatus.GRANTED -> "granted"
    PermissionsStatus.DENIED -> if (canAskAgain) "denied" else "restricted"
    else -> "undetermined"
  }
}
