package com.feer.cameralibre.camera_libre

import android.content.Context
import android.util.Log
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class H264EncoderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "H264EncoderPlugin"
        private const val METHOD_CHANNEL = "com.feer.cameralibre/h264_encoder"
    }

    private var methodChannel: MethodChannel? = null
    private var context: Context? = null
    private var textureRegistry: TextureRegistry? = null
    private var streamingEngine: H264StreamingEngine? = null

    private var activeTextureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSurface: Surface? = null
    private var isStreaming = false

    override fun onAttachedToEngine(flutterPlugin: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPlugin.applicationContext
        textureRegistry = flutterPlugin.textureRegistry
        streamingEngine = H264StreamingEngine(flutterPlugin.applicationContext)
        
        methodChannel = MethodChannel(flutterPlugin.binaryMessenger, METHOD_CHANNEL).apply {
            setMethodCallHandler(this@H264EncoderPlugin)
        }
        Log.i(TAG, "Attached to engine, streaming channel registered.")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopStreamingEngine()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        textureRegistry = null
        context = null
        streamingEngine = null
        Log.i(TAG, "Detached from engine.")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createTexture" -> {
                val registry = textureRegistry
                if (registry == null) {
                    result.error("REGISTRY_ERROR", "Texture registry is null", null)
                    return
                }
                
                try {
                    // Release any active texture first
                    activeTextureEntry?.release()
                    activeTextureEntry = null

                    val entry = registry.createSurfaceTexture()
                    activeTextureEntry = entry
                    Log.i(TAG, "Created Flutter native preview texture with ID: ${entry.id()}")
                    result.success(mapOf("textureId" to entry.id()))
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to create SurfaceTexture", e)
                    result.error("TEXTURE_CREATE_FAILED", e.message, null)
                }
            }
            "releaseTexture" -> {
                try {
                    previewSurface?.release()
                    previewSurface = null
                    activeTextureEntry?.release()
                    activeTextureEntry = null
                    Log.i(TAG, "Released active Flutter native preview texture.")
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to release texture", e)
                    result.error("TEXTURE_RELEASE_FAILED", e.message, null)
                }
            }
            "start" -> {
                val width = call.argument<Int>("width") ?: 1280
                val height = call.argument<Int>("height") ?: 720
                val fps = call.argument<Int>("fps") ?: 30
                val bitrate = call.argument<Int>("bitrate") ?: 2_000_000
                val serverIp = call.argument<String>("serverIp")
                val serverPort = call.argument<Int>("serverPort") ?: 8080
                val cameraId = call.argument<String>("cameraId") ?: "0"
                val textureId = call.argument<Int>("textureId")

                if (serverIp == null) {
                    result.error("INVALID_ARGS", "serverIp cannot be null", null)
                    return
                }

                val engine = streamingEngine
                if (engine == null) {
                    result.error("ENGINE_NULL", "Streaming engine is not initialized", null)
                    return
                }

                // Setup preview surface from the texture entry if matching textureId is provided
                val texEntry = activeTextureEntry
                if (texEntry != null && textureId != null && texEntry.id() == textureId.toLong()) {
                    try {
                        previewSurface?.release()
                        val surfaceTexture = texEntry.surfaceTexture()
                        surfaceTexture.setDefaultBufferSize(width, height)
                        previewSurface = Surface(surfaceTexture)
                        Log.i(TAG, "Preview surface successfully bound to texture $textureId.")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to build preview surface from texture ID $textureId", e)
                    }
                } else {
                    Log.w(TAG, "No matching texture ID found for preview. Running stream only.")
                }

                val success = engine.start(
                    cameraId = cameraId,
                    width = width,
                    height = height,
                    fps = fps,
                    bitrate = bitrate,
                    serverIp = serverIp,
                    serverPort = serverPort,
                    previewSurface = previewSurface
                )

                isStreaming = success
                result.success(success)
            }
            "stop" -> {
                stopStreamingEngine()
                result.success(true)
            }
            "getStats" -> {
                val engine = streamingEngine
                if (engine != null) {
                    result.success(mapOf(
                        "fps" to engine.fpsCount,
                        "bytesSent" to engine.bytesSentCount,
                        "isConnected" to engine.isConnected
                    ))
                } else {
                    result.success(mapOf(
                        "fps" to 0.0,
                        "bytesSent" to 0L,
                        "isConnected" to false
                    ))
                }
            }
            "isRunning" -> {
                result.success(isStreaming)
            }
            // Retain stubs for old methods to prevent crashing old code during migration
            "pushFrame", "pollOutput" -> {
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun stopStreamingEngine() {
        Log.i(TAG, "Stopping streaming engine and releasing textures...")
        isStreaming = false
        try {
            streamingEngine?.stop()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop streaming engine", e)
        }

        try {
            previewSurface?.release()
        } catch (_: Exception) {}
        previewSurface = null

        try {
            activeTextureEntry?.release()
        } catch (_: Exception) {}
        activeTextureEntry = null
        Log.i(TAG, "Streaming engine fully stopped and resources released.")
    }
}
