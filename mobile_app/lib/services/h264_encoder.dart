import 'dart:async';
import 'package:flutter/services.dart';

class H264Encoder {
  static const _channel = MethodChannel('com.feer.cameralibre/h264_encoder');

  bool _isRunning = false;
  int? _textureId;

  int? get textureId => _textureId;
  bool get isRunning => _isRunning;

  /// Allocates a native hardware-accelerated preview texture in Flutter's engine.
  /// Returns the texture ID.
  Future<int?> createTexture() async {
    try {
      final Map? res = await _channel.invokeMapMethod('createTexture');
      if (res != null) {
        _textureId = res['textureId'] as int?;
        return _textureId;
      }
    } on PlatformException catch (e) {
      print('[H264Encoder] Failed to create native texture: $e');
    }
    return null;
  }

  /// Releases the native hardware-accelerated preview texture.
  Future<void> releaseTexture() async {
    try {
      await _channel.invokeMethod('releaseTexture');
      _textureId = null;
    } on PlatformException catch (e) {
      print('[H264Encoder] Failed to release native texture: $e');
    }
  }

  /// Starts the native zero-copy camera capture, H.264 hardware encoding,
  /// and TCP streaming directly from Android native code to the PC server.
  Future<bool> start({
    required int width,
    required int height,
    required int fps,
    required int bitrate,
    required String serverIp,
    required int serverPort,
    String cameraId = '0',
    int? textureId,
  }) async {
    if (_isRunning) return true;

    try {
      final bool? success = await _channel.invokeMethod('start', {
        'width': width,
        'height': height,
        'fps': fps,
        'bitrate': bitrate,
        'serverIp': serverIp,
        'serverPort': serverPort,
        'cameraId': cameraId,
        'textureId': textureId,
      });
      _isRunning = success ?? false;
      return _isRunning;
    } on PlatformException catch (e) {
      print('[H264Encoder] Native start error: $e');
      _isRunning = false;
      return false;
    }
  }

  /// Stops the native zero-copy streaming session and releases textures.
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    try {
      await _channel.invokeMethod('stop');
      await releaseTexture();
    } on PlatformException catch (e) {
      print('[H264Encoder] Native stop error: $e');
    }
  }

  /// Returns active native stats: fps (double), bytesSent (int), isConnected (bool)
  Future<Map<String, dynamic>> getStats() async {
    try {
      final Map? stats = await _channel.invokeMapMethod('getStats');
      if (stats != null) {
        return {
          'fps': stats['fps'] as double? ?? 0.0,
          'bytesSent': stats['bytesSent'] as int? ?? 0,
          'isConnected': stats['isConnected'] as bool? ?? false,
        };
      }
    } on PlatformException catch (e) {
      print('[H264Encoder] Failed to get native stats: $e');
    }
    return {
      'fps': 0.0,
      'bytesSent': 0,
      'isConnected': false,
    };
  }
}
