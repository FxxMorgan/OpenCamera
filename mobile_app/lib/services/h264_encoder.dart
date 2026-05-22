import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class H264Encoder {
  static const _channel = MethodChannel('com.feer.cameralibre/h264_encoder');

  Timer? _pollTimer;
  bool _isRunning = false;
  bool _encoderReady = false;
  int _chunksReceived = 0;

  int get chunksReceived => _chunksReceived;

  /// Starts the hardware H.264 encoder.
  /// Uses MethodChannel polling instead of EventChannel for reliability.
  Future<void> start({
    required int width,
    required int height,
    required int fps,
    required int bitrate,
    required void Function(Uint8List chunk) onH264Chunk,
  }) async {
    if (_isRunning) return;

    _chunksReceived = 0;
    _encoderReady = false;

    await _channel.invokeMethod('start', {
      'width': width,
      'height': height,
      'fps': fps,
      'bitrate': bitrate,
    });

    _isRunning = true;
    _encoderReady = true;

    // Direct push notification instead of polling timer
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFrameEncoded') {
        final chunk = call.arguments as Uint8List;
        _chunksReceived++;
        onH264Chunk(chunk);
      }
    });
  }

  /// Push a YUV420_888 frame to be encoded.
  Future<void> pushYuvFrame({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int width,
    required int height,
  }) async {
    if (!_isRunning) return;
    try {
      await _channel.invokeMethod('pushFrame', {
        'yPlane': yPlane,
        'uPlane': uPlane,
        'vPlane': vPlane,
        'yRowStride': yRowStride,
        'uvRowStride': uvRowStride,
        'uvPixelStride': uvPixelStride,
        'width': width,
        'height': height,
      });
    } catch (e) {
      debugPrint('[H264Encoder] Push error: $e');
    }
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    _encoderReady = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod('stop');
  }

  bool get isRunning => _isRunning;
}
