package com.feer.cameralibre.camera_libre

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.camera2.*
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Range
import android.view.Surface
import java.io.OutputStream
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder

class H264StreamingEngine(private val context: Context) {
    companion object {
        private const val TAG = "H264StreamingEngine"
        private const val MAGIC = 0x434C4652 // "CLFR" Magic number
    }

    private var cameraDevice: CameraDevice? = null
    private var mediaCodec: MediaCodec? = null
    private var encoderInputSurface: Surface? = null
    private var captureSession: CameraCaptureSession? = null
    private var socket: Socket? = null
    private var outputStream: OutputStream? = null
    
    @Volatile
    private var isRunning = false

    private var cameraThread: HandlerThread? = null
    private var cameraHandler: Handler? = null
    private var codecThread: HandlerThread? = null
    private var codecHandler: Handler? = null

    // Real-time statistics
    @Volatile
    var fpsCount = 0.0
    @Volatile
    var bytesSentCount = 0L
    @Volatile
    var isConnected = false

    private var lastFpsTime = 0L
    private var framesThisSecond = 0

    @SuppressLint("MissingPermission")
    fun start(
        cameraId: String,
        width: Int,
        height: Int,
        fps: Int,
        bitrate: Int,
        serverIp: String,
        serverPort: Int,
        previewSurface: Surface?
    ): Boolean {
        if (isRunning) {
            Log.w(TAG, "Streaming engine already running, stopping it first.")
            stop()
        }

        Log.i(TAG, "Starting native zero-copy streaming: ${width}x${height} @ ${fps}fps, ${bitrate}bps to ${serverIp}:${serverPort}")
        isRunning = true
        isConnected = false
        bytesSentCount = 0L
        fpsCount = 0.0
        framesThisSecond = 0
        lastFpsTime = System.currentTimeMillis()

        // 1. Initialize background worker threads
        cameraThread = HandlerThread("CameraThread").apply { start() }
        cameraHandler = Handler(cameraThread!!.looper)
        
        codecThread = HandlerThread("CodecThread").apply { start() }
        codecHandler = Handler(codecThread!!.looper)

        // 2. Setup socket in background
        codecHandler?.post {
            try {
                Log.i(TAG, "Connecting TCP socket to $serverIp:$serverPort...")
                socket = Socket(serverIp, serverPort).apply {
                    tcpNoDelay = true
                    sendBufferSize = 512 * 1024 // 512 KB socket buffer
                }
                outputStream = socket?.getOutputStream()
                isConnected = true
                Log.i(TAG, "TCP socket connected successfully!")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to connect TCP socket to $serverIp:$serverPort", e)
                isConnected = false
            }
        }

        try {
            // 3. Configure MediaCodec for Zero-Copy H.264 Surface Input
            // Surface input does not require manual width alignment on the JVM heap.
            // Using the original width prevents green line / padding artifacts at the receiver.
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }

            mediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            mediaCodec?.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoderInputSurface = mediaCodec?.createInputSurface()
            mediaCodec?.start()
            Log.i(TAG, "MediaCodec initialized with Surface Input.")

            // 4. Start NAL unit draining thread loop
            codecHandler?.post { drainEncoder() }

            // 5. Initialize Camera2 and target both preview and encoder surfaces
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            cameraHandler?.post {
                try {
                    cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                        override fun onOpened(camera: CameraDevice) {
                            Log.i(TAG, "Camera $cameraId opened successfully.")
                            cameraDevice = camera
                            setupCaptureSession(camera, previewSurface, fps)
                        }

                        override fun onDisconnected(camera: CameraDevice) {
                            Log.w(TAG, "Camera $cameraId disconnected.")
                            stop()
                        }

                        override fun onError(camera: CameraDevice, error: Int) {
                            Log.e(TAG, "Camera $cameraId error: $error")
                            stop()
                        }
                    }, cameraHandler)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to open camera $cameraId natively", e)
                    stop()
                }
            }
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing streaming engine", e)
            stop()
            return false
        }
    }

    private fun selectBestFpsRange(camera: CameraDevice, targetFps: Int): Range<Int> {
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val chars = cameraManager.getCameraCharacteristics(camera.id)
            val ranges = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
            
            if (ranges != null && ranges.isNotEmpty()) {
                // First, look for exact match [targetFps, targetFps]
                for (range in ranges) {
                    if (range.lower == targetFps && range.upper == targetFps) {
                        Log.i(TAG, "Using exact target FPS range: $range")
                        return range
                    }
                }
                
                // Second, look for a range containing targetFps
                var bestRange: Range<Int>? = null
                for (range in ranges) {
                    if (range.upper == targetFps) {
                        if (bestRange == null || range.lower > bestRange.lower) {
                            bestRange = range
                        }
                    }
                }
                if (bestRange != null) {
                    Log.i(TAG, "Using upper-match target FPS range: $bestRange")
                    return bestRange
                }
                
                // Third, just find the range with upper closest to targetFps
                var closestRange = ranges[0]
                var minDiff = Math.abs(closestRange.upper - targetFps)
                for (range in ranges) {
                    val diff = Math.abs(range.upper - targetFps)
                    if (diff < minDiff) {
                        minDiff = diff
                        closestRange = range
                    }
                }
                Log.i(TAG, "Using closest match target FPS range: $closestRange")
                return closestRange
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error selecting FPS range", e)
        }
        // Fallback to safe range
        return Range(15, 30)
    }

    private fun setupCaptureSession(camera: CameraDevice, previewSurface: Surface?, fps: Int) {
        val targets = mutableListOf<Surface>()
        encoderInputSurface?.let { targets.add(it) }
        previewSurface?.let { targets.add(it) }

        if (targets.isEmpty()) {
            Log.e(TAG, "No valid targets for capture session.")
            stop()
            return
        }

        try {
            camera.createCaptureSession(targets, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    if (!isRunning) {
                        session.close()
                        return
                    }
                    Log.i(TAG, "Camera capture session configured successfully.")
                    captureSession = session
                    
                    try {
                        val builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                            targets.forEach { addTarget(it) }
                            // Dynamically select target FPS range to prevent crashes on front camera / budget devices
                            val fpsRange = selectBestFpsRange(camera, fps)
                            set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange)

                            // Boost exposure compensation to brighten the image.
                            // TEMPLATE_RECORD tends to be darker than TEMPLATE_PREVIEW.
                            try {
                                val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                                val chars = cameraManager.getCameraCharacteristics(camera.id)
                                val aeRange = chars.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
                                if (aeRange != null) {
                                    // Apply +4 EV steps, clamped to device's supported range
                                    val boost = 4.coerceAtMost(aeRange.upper)
                                    set(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, boost)
                                    Log.i(TAG, "AE exposure compensation set to +$boost (range: $aeRange)")
                                }
                            } catch (aeEx: Exception) {
                                Log.w(TAG, "Could not set AE exposure compensation", aeEx)
                            }
                        }
                        session.setRepeatingRequest(builder.build(), null, cameraHandler)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to set repeating request", e)
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(TAG, "Failed to configure camera capture session.")
                    stop()
                }
            }, cameraHandler)
        } catch (e: Exception) {
            Log.e(TAG, "Error creating capture session", e)
            stop()
        }
    }

    private fun drainEncoder() {
        val info = MediaCodec.BufferInfo()
        val headerBuffer = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)

        Log.i(TAG, "Started encoder drain loop.")
        while (isRunning) {
            val codec = mediaCodec ?: break
            try {
                val idx = codec.dequeueOutputBuffer(info, 10000)
                if (idx >= 0) {
                    val buffer = codec.getOutputBuffer(idx)
                    if (buffer != null && info.size > 0) {
                        val size = info.size
                        
                        // Extract NAL unit payload
                        val payload = ByteArray(size)
                        buffer.position(info.offset)
                        buffer.limit(info.offset + size)
                        buffer.get(payload)

                        // If connected, write the custom protocol to socket:
                        // [MAGIC: 4 bytes Little Endian][SIZE: 4 bytes Little Endian][DATA: size bytes]
                        val out = outputStream
                        if (out != null && isConnected) {
                            try {
                                headerBuffer.clear()
                                headerBuffer.putInt(MAGIC)
                                headerBuffer.putInt(size)
                                out.write(headerBuffer.array())
                                out.write(payload)
                                out.flush()
                                
                                bytesSentCount += size + 8
                                updateFpsStats()
                            } catch (socketEx: Exception) {
                                Log.e(TAG, "Socket write error, disconnecting stream", socketEx)
                                isConnected = false
                            }
                        }
                    }
                    codec.releaseOutputBuffer(idx, false)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error during dequeueOutputBuffer", e)
                // Small sleep to prevent tight loops on errors
                try { Thread.sleep(50) } catch (_: Exception) {}
            }
        }
        Log.i(TAG, "Encoder drain loop finished.")
    }

    private fun updateFpsStats() {
        framesThisSecond++
        val now = System.currentTimeMillis()
        val delta = now - lastFpsTime
        if (delta >= 1000) {
            fpsCount = (framesThisSecond * 1000.0) / delta
            framesThisSecond = 0
            lastFpsTime = now
            Log.d(TAG, "Stream Stats: FPS=${String.format("%.1f", fpsCount)} | BytesSent=$bytesSentCount")
        }
    }

    fun stop() {
        if (!isRunning) return
        Log.i(TAG, "Stopping streaming engine...")
        isRunning = false
        isConnected = false

        try {
            captureSession?.stopRepeating()
        } catch (_: Exception) {}
        
        try {
            captureSession?.close()
        } catch (_: Exception) {}
        captureSession = null

        try {
            cameraDevice?.close()
        } catch (_: Exception) {}
        cameraDevice = null

        try {
            mediaCodec?.stop()
        } catch (_: Exception) {}
        try {
            mediaCodec?.release()
        } catch (_: Exception) {}
        mediaCodec = null

        encoderInputSurface?.release()
        encoderInputSurface = null

        try {
            outputStream?.close()
        } catch (_: Exception) {}
        outputStream = null

        try {
            socket?.close()
        } catch (_: Exception) {}
        socket = null

        cameraThread?.quitSafely()
        cameraThread = null
        cameraHandler = null

        codecThread?.quitSafely()
        codecThread = null
        codecHandler = null
        Log.i(TAG, "Streaming engine stopped successfully.")
    }
}
