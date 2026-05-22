// camera_service.dart — Phase 2
// Manages camera initialization, frame capture, and JPEG encoding.
/// Architecture:
///   - CameraController from the camera package handles preview.
///   - startImageStream() delivers raw CameraImage (YUV420_888 on Android).
///   - If the device reports ImageFormatGroup.jpeg, planes[0].bytes IS the JPEG.
///   - Otherwise we use _convertYuvToJpeg() via compute() (background isolate)
///     to do the YUV→RGB→JPEG conversion without blocking the UI thread.
///   - onJpegFrame callback delivers Uint8List JPEG bytes at the target FPS.

import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// ---------------------------------------------------------------------------
//  Data class passed to the compute isolate
// ---------------------------------------------------------------------------

class _YuvData {
  final Uint8List yPlane;
  final Uint8List uPlane;
  final Uint8List vPlane;
  final int width;
  final int height;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final int targetWidth;  // scale-down target (0 = no scale)
  final int jpegQuality;

  const _YuvData({
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.targetWidth,
    required this.jpegQuality,
  });
}

// ---------------------------------------------------------------------------
//  Top-level function for compute() — runs in a separate isolate
// ---------------------------------------------------------------------------

Uint8List _encodeYuvToJpeg(_YuvData d) {
  // Build RGB image from YUV420_888 planes
  final image = img.Image(width: d.width, height: d.height);

  for (int y = 0; y < d.height; y++) {
    for (int x = 0; x < d.width; x++) {
      final int yIdx  = y * d.yRowStride + x;
      final int uvIdx = (y >> 1) * d.uvRowStride + (x >> 1) * d.uvPixelStride;

      if (yIdx  >= d.yPlane.length) continue;
      if (uvIdx >= d.uPlane.length) continue;
      if (uvIdx >= d.vPlane.length) continue;

      final yp = d.yPlane[yIdx];
      final up = d.uPlane[uvIdx];
      final vp = d.vPlane[uvIdx];

      // BT.601 YUV → RGB
      int r = (yp + 1.370705  * (vp - 128)).round().clamp(0, 255);
      int g = (yp - 0.698001  * (vp - 128) - 0.337633 * (up - 128)).round().clamp(0, 255);
      int b = (yp + 1.732446  * (up - 128)).round().clamp(0, 255);

      image.setPixelRgb(x, y, r, g, b);
    }
  }

  // Optionally scale down to reduce bandwidth
  final output = (d.targetWidth > 0 && d.targetWidth < d.width)
      ? img.copyResize(image, width: d.targetWidth)
      : image;

  return Uint8List.fromList(img.encodeJpg(output, quality: d.jpegQuality));
}

// ---------------------------------------------------------------------------
//  Quality / Resolution presets
// ---------------------------------------------------------------------------

enum StreamQuality {
  low(targetWidth: 320, jpegQuality: 60, fps: 15,
      preset: ResolutionPreset.low),
  medium(targetWidth: 640, jpegQuality: 75, fps: 20,
      preset: ResolutionPreset.medium),
  high(targetWidth: 1280, jpegQuality: 85, fps: 25,
      preset: ResolutionPreset.high);

  const StreamQuality({
    required this.targetWidth,
    required this.jpegQuality,
    required this.fps,
    required this.preset,
  });

  final int targetWidth;
  final int jpegQuality;
  final int fps;
  final ResolutionPreset preset;

  String get label => name[0].toUpperCase() + name.substring(1);
}

// ---------------------------------------------------------------------------
//  CameraService
// ---------------------------------------------------------------------------

typedef JpegFrameCallback = void Function(Uint8List jpegBytes);
typedef YuvFrameCallback = Future<void> Function({
  required Uint8List yPlane,
  required Uint8List uPlane,
  required Uint8List vPlane,
  required int yRowStride,
  required int uvRowStride,
  required int uvPixelStride,
  required int width,
  required int height,
});

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  // Streaming state
  bool _streaming = false;
  JpegFrameCallback? _onJpegFrame;
  YuvFrameCallback? _onYuvFrame;
  StreamQuality _quality = StreamQuality.medium;
  bool _useYuv = false;

  // Rate limiting: only process one frame per interval
  bool _encodingBusy = false;
  int  _frameDropped = 0;
  int  _framesSent   = 0;

  // ---------------------------------------------------------------------------
  //  Public API
  // ---------------------------------------------------------------------------

  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isStreaming    => _streaming;
  int  get framesSent     => _framesSent;
  int  get framesDropped  => _frameDropped;

  CameraController? get controller => _controller;
  StreamQuality     get quality     => _quality;

  List<CameraDescription> get cameras       => _cameras;
  int                     get selectedIndex => _selectedCameraIndex;

  /// Call once at startup to enumerate cameras.
  Future<void> initCameras() async {
    _cameras = await availableCameras();
  }

  /// Initialize the camera for preview.
  Future<void> initializeCamera({
    int cameraIndex = 0,
    StreamQuality quality = StreamQuality.medium,
    bool useYuv = false,
  }) async {
    await _disposeController();

    if (_cameras.isEmpty) await initCameras();
    if (_cameras.isEmpty) throw Exception('No cameras found on device.');

    _selectedCameraIndex = cameraIndex.clamp(0, _cameras.length - 1);
    _quality = quality;
    _useYuv = useYuv;

    _controller = CameraController(
      _cameras[_selectedCameraIndex],
      quality.preset,
      enableAudio: false,
      imageFormatGroup: useYuv ? ImageFormatGroup.yuv420 : ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
  }

  /// Start sending JPEG frames to [callback].
  Future<void> startStreaming(JpegFrameCallback callback) async {
    if (_controller == null || !isInitialized) {
      throw StateError('Camera not initialized. Call initializeCamera() first.');
    }
    if (_streaming) return;

    _onJpegFrame  = callback;
    _streaming    = true;
    _framesSent   = 0;
    _frameDropped = 0;

    await _controller!.startImageStream(_onCameraImage);
  }

  /// Start sending YUV frames to [callback] (for H.264 encoding).
  Future<void> startYuvStreaming(YuvFrameCallback callback) async {
    if (_controller == null || !isInitialized) {
      throw StateError('Camera not initialized. Call initializeCamera() first.');
    }
    if (_streaming) return;

    _onYuvFrame = callback;
    _streaming  = true;
    _framesSent = 0;
    _frameDropped = 0;

    await _controller!.startImageStream(_onCameraImage);
  }

  /// Stop streaming and release the image stream.
  Future<void> stopStreaming() async {
    if (!_streaming) return;
    _streaming = false;
    _onJpegFrame = null;
    _onYuvFrame = null;
    if (_controller?.value.isStreamingImages ?? false) {
      await _controller!.stopImageStream();
    }
  }

  /// Switch between front and back camera.
  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;
    final wasStreaming = _streaming;
    final yuvCb = _onYuvFrame;
    final jpegCb = _onJpegFrame;
    if (wasStreaming) await stopStreaming();

    final newIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await initializeCamera(cameraIndex: newIndex, quality: _quality, useYuv: _useYuv);

    if (wasStreaming) {
      if (yuvCb != null) {
        await startYuvStreaming(yuvCb);
      } else if (jpegCb != null) {
        await startStreaming(jpegCb);
      }
    }
  }

  /// Change quality preset (restarts camera if needed).
  Future<void> setQuality(StreamQuality q) async {
    if (q == _quality) return;
    final wasStreaming = _streaming;
    final yuvCb = _onYuvFrame;
    final jpegCb = _onJpegFrame;
    if (wasStreaming) await stopStreaming();

    await initializeCamera(cameraIndex: _selectedCameraIndex, quality: q, useYuv: _useYuv);

    if (wasStreaming) {
      if (yuvCb != null) {
        await startYuvStreaming(yuvCb);
      } else if (jpegCb != null) {
        await startStreaming(jpegCb);
      }
    }
  }

  Future<void> dispose() async {
    await stopStreaming();
    await _disposeController();
  }

  // ---------------------------------------------------------------------------
  //  Private
  // ---------------------------------------------------------------------------

  Future<void> _disposeController() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
  }

  void _onCameraImage(CameraImage image) {
    if (!_streaming) return;

    // Drop frame if still encoding the previous one (rate limiting)
    if (_encodingBusy) {
      _frameDropped++;
      return;
    }

    _encodingBusy = true;

    // YUV mode — deliver raw planes to H.264 encoder (with backpressure)
    // We only set _encodingBusy = false when the JNI push completes,
    // thereby skipping camera frames if the queue/JNI is busy.
    if (_useYuv && _onYuvFrame != null) {
      if (image.planes.length >= 3) {
        _onYuvFrame!(
          yPlane:        image.planes[0].bytes,
          uPlane:        image.planes[1].bytes,
          vPlane:        image.planes[2].bytes,
          yRowStride:    image.planes[0].bytesPerRow,
          uvRowStride:   image.planes[1].bytesPerRow,
          uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
          width:         image.width,
          height:        image.height,
        ).then((_) {
          _encodingBusy = false;
        }).catchError((_) {
          _encodingBusy = false;
        });
        _framesSent++;
      } else {
        _encodingBusy = false;
      }
      return;
    }

    // JPEG mode
    if (image.format.group == ImageFormatGroup.jpeg) {
      if (_onJpegFrame != null) {
        final bytes = image.planes[0].bytes;
        _framesSent++;
        _onJpegFrame!(Uint8List.fromList(bytes));
      }
      _encodingBusy = false;
      return;
    }

    // Fallback: YUV420 → JPEG in compute isolate
    if (image.planes.length < 3 || _onJpegFrame == null) {
      _encodingBusy = false;
      return;
    }

    final data = _YuvData(
      yPlane:        image.planes[0].bytes,
      uPlane:        image.planes[1].bytes,
      vPlane:        image.planes[2].bytes,
      width:         image.width,
      height:        image.height,
      yRowStride:    image.planes[0].bytesPerRow,
      uvRowStride:   image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
      targetWidth:   _quality.targetWidth,
      jpegQuality:   _quality.jpegQuality,
    );

    compute(_encodeYuvToJpeg, data).then((jpegBytes) {
      if (_streaming && _onJpegFrame != null) {
        _framesSent++;
        _onJpegFrame!(jpegBytes);
      }
    }).catchError((e) {
      debugPrint('[CameraService] Encode error: $e');
    }).whenComplete(() {
      _encodingBusy = false;
    });
  }
}
