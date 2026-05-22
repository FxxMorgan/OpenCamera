package com.feer.cameralibre.camera_libre

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean

class H264EncoderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "H264Encoder"
        private const val METHOD_CHANNEL = "com.feer.cameralibre/h264_encoder"
        private val START_CODE = byteArrayOf(0x00, 0x00, 0x00, 0x01)
    }

    private val queueLock = Object()
    private var methodChannel: MethodChannel? = null
    private var mediaCodec: MediaCodec? = null
    private var encodingThread: Thread? = null
    private val isRunning = AtomicBoolean(false)
    private val frameQueue = ArrayDeque<FrameData>()
    private var baseBitrate = 2_000_000
    private var currentBitrate = 2_000_000
    private var codecWidth = 0
    private var codecHeight = 0
    private val mainHandler = Handler(Looper.getMainLooper())

    // Thread-safe output buffer for H.264 chunks
    private val outputQueue = CopyOnWriteArrayList<ByteArray>()

    private var spsPpsHeader: ByteArray? = null
    private var sentSpsPps = false
    private var spsNal: ByteArray? = null
    private var ppsNal: ByteArray? = null
    private var basePts = 0L

    data class FrameData(
        val yPlane: ByteArray,
        val uPlane: ByteArray,
        val vPlane: ByteArray,
        val yRowStride: Int,
        val uvRowStride: Int,
        val uvPixelStride: Int,
        val width: Int,
        val height: Int
    )

    override fun onAttachedToEngine(flutterPlugin: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(flutterPlugin.binaryMessenger, METHOD_CHANNEL).apply {
            setMethodCallHandler(this@H264EncoderPlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopEncoder()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val w = call.argument<Int>("width") ?: 640
                val h = call.argument<Int>("height") ?: 480
                val f = call.argument<Int>("fps") ?: 20
                val b = call.argument<Int>("bitrate") ?: 2_000_000
                startEncoder(w, h, f, b)
                result.success(true)
            }
            "stop" -> {
                stopEncoder()
                result.success(true)
            }
            "pushFrame" -> {
                val yPlane = call.argument<ByteArray>("yPlane")
                val uPlane = call.argument<ByteArray>("uPlane")
                val vPlane = call.argument<ByteArray>("vPlane")
                val yRowStride = call.argument<Int>("yRowStride") ?: 0
                val uvRowStride = call.argument<Int>("uvRowStride") ?: 0
                val uvPixelStride = call.argument<Int>("uvPixelStride") ?: 1
                val w = call.argument<Int>("width") ?: codecWidth
                val h = call.argument<Int>("height") ?: codecHeight

                if (yPlane != null && uPlane != null && vPlane != null && isRunning.get()) {
                    synchronized(queueLock) {
                        if (frameQueue.size > 5) {
                            frameQueue.removeFirst()
                        }
                        frameQueue.addLast(
                            FrameData(yPlane, uPlane, vPlane, yRowStride, uvRowStride, uvPixelStride, w, h)
                        )
                        queueLock.notify()
                    }
                }
                result.success(null)
            }
            "pollOutput" -> {
                val pending = ArrayList<ByteArray>(outputQueue)
                outputQueue.clear()
                result.success(pending)
            }
            "isRunning" -> {
                result.success(isRunning.get())
            }
            else -> result.notImplemented()
        }
    }

    private fun startEncoder(w: Int, h: Int, f: Int, b: Int) {
        if (isRunning.get()) { Log.w(TAG, "Already running"); return }

        // Align width to 32 bytes for hardware encoder compatibility
        val alignment = 32
        val alignedWidth = (w + alignment - 1) and (alignment - 1).inv()

        baseBitrate = b
        currentBitrate = b
        codecWidth = w; codecHeight = h
        spsPpsHeader = null; sentSpsPps = false
        spsNal = null; ppsNal = null
        basePts = 0L
        outputQueue.clear()

        try {
            val codec = MediaCodec.createEncoderByType("video/avc")
            val format = MediaFormat.createVideoFormat("video/avc", alignedWidth, h).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
                setInteger(MediaFormat.KEY_BIT_RATE, b)
                setInteger(MediaFormat.KEY_FRAME_RATE, f)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                if (Build.VERSION.SDK_INT >= 29) {
                    setInteger(MediaFormat.KEY_PREPEND_HEADER_TO_SYNC_FRAMES, 1)
                }
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()

            extractSpsPpsFromFormat(codec.outputFormat)
            mediaCodec = codec

            isRunning.set(true)
            encodingThread = Thread({ encodingLoop(alignedWidth) }, "H264EncoderThread").apply {
                isDaemon = true; start()
            }
            Log.i(TAG, "Encoder started: ${alignedWidth}x${h} (native ${w}x${h}) @ ${f}fps, ${b/1000}kbps")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start encoder", e)
        }
    }

    private fun stopEncoder() {
        if (!isRunning.get()) return
        isRunning.set(false)
        synchronized(queueLock) { queueLock.notify() }
        encodingThread?.join(2000); encodingThread = null
        try { mediaCodec?.stop(); mediaCodec?.release() } catch (_: Exception) {}
        mediaCodec = null
        frameQueue.clear(); outputQueue.clear()
        spsPpsHeader = null; sentSpsPps = false
        spsNal = null; ppsNal = null
        Log.i(TAG, "Encoder stopped")
    }

    private fun encodingLoop(configuredWidth: Int) {
        val codec = mediaCodec ?: return
        val bufferInfo = MediaCodec.BufferInfo()
        var frameCounter = 0L
        var lastBitrateAdjustTime = System.currentTimeMillis()

        var stride = configuredWidth
        var sliceHeight = codecHeight
        try {
            val inputFormat = codec.inputFormat
            if (inputFormat.containsKey(MediaFormat.KEY_STRIDE)) {
                val s = inputFormat.getInteger(MediaFormat.KEY_STRIDE)
                if (s > 0) stride = s
            }
            if (inputFormat.containsKey(MediaFormat.KEY_SLICE_HEIGHT)) {
                val sh = inputFormat.getInteger(MediaFormat.KEY_SLICE_HEIGHT)
                if (sh > 0) sliceHeight = sh
            }
            Log.i(TAG, "MediaCodec inputFormat stride=$stride, sliceHeight=$sliceHeight")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to query input format stride/sliceHeight, using dimensions ${codecWidth}x${codecHeight}", e)
        }

        var firstFrameLogged = false

        while (isRunning.get() || frameQueue.isNotEmpty()) {
            var frame: FrameData? = null
            synchronized(queueLock) {
                while (frameQueue.isEmpty() && isRunning.get()) {
                    try { queueLock.wait(100) } catch (_: InterruptedException) {}
                }
                if (frameQueue.isNotEmpty()) frame = frameQueue.removeFirst()
            }
            if (frame == null && !isRunning.get()) break
            if (frame == null) continue

            val now = System.currentTimeMillis()
            if (now - lastBitrateAdjustTime > 500) {
                val qSize = synchronized(queueLock) { frameQueue.size }
                var targetBitrate = currentBitrate

                if (qSize > 3) {
                    targetBitrate = (baseBitrate * 0.2).toInt()
                } else if (qSize > 1) {
                    targetBitrate = (baseBitrate * 0.5).toInt()
                } else {
                    targetBitrate = baseBitrate
                }

                if (targetBitrate != currentBitrate) {
                    currentBitrate = targetBitrate
                    val params = Bundle()
                    params.putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, currentBitrate)
                    if (targetBitrate < baseBitrate) {
                        params.putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
                    }
                    try {
                        codec.setParameters(params)
                        Log.i(TAG, "Adaptive Bitrate: adjusted to ${currentBitrate / 1000}kbps (raw queue size: $qSize)")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to set bitrate parameters", e)
                    }
                }
                lastBitrateAdjustTime = now
            }

            try {
                val idx = codec.dequeueInputBuffer(0)
                if (idx >= 0) {
                    val buf = codec.getInputBuffer(idx)!!

                    val cap = buf.capacity()
                    val fullSize = stride * sliceHeight * 3 / 2

                    if (!firstFrameLogged) {
                        firstFrameLogged = true
                        Log.i(TAG, "=== FIRST FRAME DIAGNOSTICS ===")
                        Log.i(TAG, "  codecWidth=$codecWidth  codecHeight=$codecHeight")
                        Log.i(TAG, "  stride=$stride  sliceHeight=$sliceHeight")
                        Log.i(TAG, "  buf.capacity()=$cap  fullSize=$fullSize")
                        Log.i(TAG, "  frame.width=${frame.width}  frame.height=${frame.height}")
                        Log.i(TAG, "  frame.yRowStride=${frame.yRowStride}")
                        Log.i(TAG, "  frame.uvRowStride=${frame.uvRowStride}")
                        Log.i(TAG, "  frame.uvPixelStride=${frame.uvPixelStride}")
                        Log.i(TAG, "  frame.yPlane.size=${frame.yPlane.size}")
                        Log.i(TAG, "  frame.uPlane.size=${frame.uPlane.size}")
                        Log.i(TAG, "================================")
                    }

                    buf.clear()
                    copyYuvToBuffer(buf, frame, codecWidth, codecHeight, stride, sliceHeight)
                    
                    val currentNanoseconds = System.nanoTime()
                    if (basePts == 0L) {
                        basePts = currentNanoseconds / 1000
                    }
                    val pts = (currentNanoseconds / 1000) - basePts
                    
                    // Always tell the codec the full expected buffer size (stride * sliceHeight * 3/2)
                    // clamped to actual capacity. Partial size causes UV truncation (green bar).
                    val queuedSize = minOf(cap, fullSize)
                    codec.queueInputBuffer(idx, 0, queuedSize, pts, 0)
                }
            } catch (e: Exception) { Log.e(TAG, "Input error", e); continue }
            drainOutput(codec, bufferInfo)
        }
        try {
            val idx = codec.dequeueInputBuffer(0)
            if (idx >= 0) codec.queueInputBuffer(idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            drainOutput(codec, bufferInfo)
        } catch (_: Exception) {}
    }

    private fun copyYuvToBuffer(buffer: ByteBuffer, frame: FrameData, w: Int, h: Int, stride: Int, sliceHeight: Int) {
        val cap = buffer.capacity()

        // ── Y plane ──────────────────────────────────────────────────────────
        if (frame.yRowStride == stride && w == stride) {
            val copyLen = minOf(frame.yPlane.size, cap)
            buffer.position(0)
            buffer.put(frame.yPlane, 0, copyLen)
        } else {
            for (y in 0 until h) {
                val srcOff = y * frame.yRowStride
                val dstOff = y * stride
                val copyLen = minOf(w, frame.yPlane.size - srcOff, cap - dstOff)
                if (copyLen <= 0) break
                buffer.position(dstOff)
                buffer.put(frame.yPlane, srcOff, copyLen)
            }
        }

        // ── UV plane (NV12: interleaved U,V) ─────────────────────────────────
        val uvH = h / 2
        val uvW = w / 2
        val uvBase = stride * sliceHeight

        if (frame.uvPixelStride == 2) {
            // Android planes[1] (uPlane) = [U0,V0,U1,V1,...] → NV12 order
            // Android planes[2] (vPlane) = [V0,U0,V1,U1,...] → NV21 order
            // Most Qualcomm/MediaTek hardware encoders with COLOR_FormatYUV420Flexible
            // expect NV21 (V first). Use vPlane to get correct color order.
            val uvPlane = frame.vPlane  // NV21: V,U interleaved — correct for most HW
            if (frame.uvRowStride == stride && uvW * 2 == stride) {
                val copyLen = minOf(uvPlane.size, cap - uvBase)
                if (copyLen > 0) {
                    buffer.position(uvBase)
                    buffer.put(uvPlane, 0, copyLen)
                }
            } else {
                for (y in 0 until uvH) {
                    val srcOff = y * frame.uvRowStride
                    val dstOff = uvBase + y * stride
                    val copyLen = minOf(uvW * 2, uvPlane.size - srcOff, cap - dstOff)
                    if (copyLen <= 0) break
                    buffer.position(dstOff)
                    buffer.put(uvPlane, srcOff, copyLen)
                }
            }
        } else {
            // Planar I420: U and V separate, uvPixelStride == 1
            val uStride = stride / 2
            val uSliceH = sliceHeight / 2
            val uBase   = uvBase
            val vBase   = uvBase + uStride * uSliceH

            for (y in 0 until uvH) {
                val srcOff = y * frame.uvRowStride
                val dstOff = uBase + y * uStride
                val copyLen = minOf(uvW, frame.uPlane.size - srcOff, cap - dstOff)
                if (copyLen <= 0) break
                buffer.position(dstOff)
                buffer.put(frame.uPlane, srcOff, copyLen)
            }
            for (y in 0 until uvH) {
                val srcOff = y * frame.uvRowStride
                val dstOff = vBase + y * uStride
                val copyLen = minOf(uvW, frame.vPlane.size - srcOff, cap - dstOff)
                if (copyLen <= 0) break
                buffer.position(dstOff)
                buffer.put(frame.vPlane, srcOff, copyLen)
            }
        }
    }

    private fun drainOutput(codec: MediaCodec, bufferInfo: MediaCodec.BufferInfo) {
        while (true) {
            val idx = codec.dequeueOutputBuffer(bufferInfo, 0)
            if (idx == MediaCodec.INFO_TRY_AGAIN_LATER) break
            if (idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) { extractSpsPpsFromFormat(codec.outputFormat); continue }
            if (idx < 0) break
            try {
                val buf = codec.getOutputBuffer(idx)!!
                val size = bufferInfo.size
                if (size > 0) {
                    val data = ByteArray(size); buf.get(data); buf.position(0)
                    val isConfig = bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    val isKey = bufferInfo.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0

                    if (isConfig) {
                        spsPpsHeader = toAnnexB(data)
                        Log.i(TAG, "SPS/PPS extracted from CODEC_CONFIG: ${spsPpsHeader!!.size} bytes")
                        codec.releaseOutputBuffer(idx, false)
                        continue
                    }

                    val annexB = toAnnexB(data)
                    if (spsPpsHeader == null) extractSpsPpsFromAnnexB(annexB)

                    val payload = if (isKey && spsPpsHeader != null) {
                        spsPpsHeader!! + annexB
                    } else {
                        annexB
                    }
                    
                    // Directly push frame to Dart on Main UI thread
                    mainHandler.post {
                        methodChannel?.invokeMethod("onFrameEncoded", payload)
                    }
                }
                codec.releaseOutputBuffer(idx, false)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            } catch (e: Exception) { Log.e(TAG, "Output error", e); codec.releaseOutputBuffer(idx, false); break }
        }
    }

    private fun extractSpsPpsFromFormat(format: MediaFormat) {
        if (spsPpsHeader != null) return
        val csd0 = format.getByteBuffer("csd-0"); val csd1 = format.getByteBuffer("csd-1")
        if (csd0 != null && csd1 != null) {
            val sps = ByteArray(csd0.remaining()); csd0.get(sps)
            val pps = ByteArray(csd1.remaining()); csd1.get(pps)
            spsPpsHeader = buildAnnexBHeader(sps, pps)
            Log.i(TAG, "SPS/PPS extracted from format: ${spsPpsHeader!!.size} bytes")
        }
    }

    private fun extractSpsPpsFromAnnexB(data: ByteArray) {
        var i = 0
        while (i + 4 < data.size) {
            val start = findStartCode(data, i) ?: break
            val next = findStartCode(data, start + 4) ?: data.size
            val nalStart = start + if (data[start + 2] == 1.toByte()) 3 else 4
            if (nalStart >= data.size) break
            val nalType = data[nalStart].toInt() and 0x1F
            val nal = data.copyOfRange(start, next)
            if (nalType == 7) spsNal = nal else if (nalType == 8) ppsNal = nal
            if (spsNal != null && ppsNal != null) {
                spsPpsHeader = buildAnnexBHeader(stripStartCode(spsNal!!), stripStartCode(ppsNal!!))
                Log.i(TAG, "SPS/PPS extracted from stream: ${spsPpsHeader!!.size} bytes")
                break
            }
            i = next
        }
    }

    private fun buildAnnexBHeader(sps: ByteArray, pps: ByteArray): ByteArray {
        val has = { d: ByteArray -> d.size >= 4 && d[0] == 0.toByte() && d[1] == 0.toByte() && d[2] == 0.toByte() && d[3] == 1.toByte() }
        val sb = ByteArrayOutputStream()
        if (!has(sps)) sb.write(START_CODE); sb.write(sps)
        if (!has(pps)) sb.write(START_CODE); sb.write(pps)
        return sb.toByteArray()
    }

    private fun toAnnexB(input: ByteArray): ByteArray {
        if (input.size < 4) return input
        if ((input[0] == 0.toByte() && input[1] == 0.toByte() && input[2] == 0.toByte() && input[3] == 1.toByte()) ||
            (input[0] == 0.toByte() && input[1] == 0.toByte() && input[2] == 1.toByte())) return input
        val out = ByteArrayOutputStream(); var i = 0
        while (i + 4 <= input.size) {
            val len = ((input[i].toInt() and 0xFF) shl 24) or ((input[i+1].toInt() and 0xFF) shl 16) or
                      ((input[i+2].toInt() and 0xFF) shl 8) or (input[i+3].toInt() and 0xFF)
            i += 4
            if (len <= 0 || i + len > input.size) break
            out.write(START_CODE); out.write(input, i, len); i += len
        }
        val c = out.toByteArray(); return if (c.isNotEmpty()) c else input
    }

    private fun findStartCode(data: ByteArray, from: Int): Int? {
        var i = from
        while (i + 3 < data.size) {
            if (data[i] == 0.toByte() && data[i+1] == 0.toByte() && data[i+2] == 1.toByte()) return i
            if (i + 4 < data.size && data[i] == 0.toByte() && data[i+1] == 0.toByte() && data[i+2] == 0.toByte() && data[i+3] == 1.toByte()) return i
            i++
        }
        return null
    }

    private fun stripStartCode(nal: ByteArray): ByteArray {
        if (nal.size >= 4 && nal[0] == 0.toByte() && nal[1] == 0.toByte() && nal[2] == 0.toByte() && nal[3] == 1.toByte())
            return nal.copyOfRange(4, nal.size)
        if (nal.size >= 3 && nal[0] == 0.toByte() && nal[1] == 0.toByte() && nal[2] == 1.toByte())
            return nal.copyOfRange(3, nal.size)
        return nal
    }
}
