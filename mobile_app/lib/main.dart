import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'services/camera_service.dart';
import 'services/h264_encoder.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  runApp(const CameraLibreApp());
}

class CameraLibreApp extends StatelessWidget {
  const CameraLibreApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cámara Libre',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// ============================================================
//  MainScreen — handles permissions then shows CameraScreen
// ============================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _permissionsGranted = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final camera = await Permission.camera.request();
    setState(() {
      _permissionsGranted = camera.isGranted;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E1A),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
      );
    }
    if (!_permissionsGranted) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt_outlined,
                    color: Color(0xFF00E5FF), size: 60),
                const SizedBox(height: 20),
                const Text('Permiso de cámara requerido',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Text(
                    'La app necesita acceso a la cámara para transmitir video.',
                    style: TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: const Color(0xFF0A0E1A),
                  ),
                  icon: const Icon(Icons.settings),
                  label: const Text('Abrir configuración'),
                  onPressed: () async {
                    await openAppSettings();
                    await _checkPermissions();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const CameraScreen();
  }
}

// ============================================================
//  CameraScreen — Fullscreen camera with overlay controls
// ============================================================

enum AppStatus { idle, connecting, connected, error }

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  // Controllers
  final _ipCtrl   = TextEditingController(text: '192.168.1.');
  final _portCtrl = TextEditingController(text: '8080');
  final _log      = <String>[];

  // State
  AppStatus  _status    = AppStatus.idle;
  String     _statusMsg = 'Desconectado';
  String?    _localIp;
  int        _framesSent = 0;
  int        _bytesSent  = 0;
  bool       _streaming  = false;

  // FPS tracking — updated via periodic timer, NOT per-frame setState
  int _displayFrames = 0;
  int _displayBytes  = 0;
  int _currentFps    = 0;
  int _lastFpsFrames = 0;
  Timer? _statsTimer;

  // Socket
  Socket? _socket;

  // Camera & Encoder
  final _cam = CameraService();
  final _h264Encoder = H264Encoder();
  bool  _cameraReady = false;
  String? _cameraError;
  StreamQuality _quality = StreamQuality.medium;
  bool _useH264 = true;
  bool _isPipelineBusy = false;
  Timer? _safetyTimer;

  // Auto-dim for battery saving
  double _previewOpacity = 1.0;
  Timer? _dimTimer;
  static const _dimDelay = Duration(seconds: 5);
  static const _dimOpacity = 0.3;

  // Animation
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  // Frame protocol magic
  static const int _magic = 0x434C4652;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadPrefs();
    _fetchLocalIp();
    _initCamera();
    _startStatsTimer();
  }

  @override
  void dispose() {
    _disconnect(silent: true);
    _safetyTimer?.cancel();
    _statsTimer?.cancel();
    _dimTimer?.cancel();
    _cam.dispose();
    _pulseCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  // ---- Stats timer (1 update/sec instead of per-frame) ----------------------

  void _startStatsTimer() {
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final fps = _framesSent - _lastFpsFrames;
      _lastFpsFrames = _framesSent;
      setState(() {
        _currentFps = fps;
        _displayFrames = _framesSent;
        _displayBytes = _bytesSent;
      });
    });
  }

  // ---- Auto-dim for battery saving ------------------------------------------

  void _resetDimTimer() {
    _dimTimer?.cancel();
    if (_previewOpacity != 1.0) {
      setState(() => _previewOpacity = 1.0);
    }
    if (_streaming) {
      _dimTimer = Timer(_dimDelay, () {
        if (mounted && _streaming) {
          setState(() => _previewOpacity = _dimOpacity);
        }
      });
    }
  }

  // ---- Camera ----------------------------------------------------------------

  Future<void> _initCamera() async {
    try {
      await _cam.initCameras();
      await _cam.initializeCamera(quality: _quality, useYuv: _useH264);
      if (mounted) setState(() {
        _cameraReady = true;
        _cameraError = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        _cameraReady = false;
        _cameraError = 'Error al inicializar cámara: $e';
      });
    }
  }

  Future<void> _startStreaming() async {
    if (!_cameraReady || _socket == null) return;
    setState(() => _streaming = true);
    _resetDimTimer();
    _appendLog('▶ Streaming iniciado (${_quality.label}, ${_useH264 ? "H.264" : "JPEG"})');

    if (_useH264) {
      _appendLog('⚙ Iniciando encoder H.264 hardware...');
      bool encoderReady = false;
      bool starting = false;
      
      _isPipelineBusy = false;
      _safetyTimer?.cancel();

      await _cam.startYuvStreaming(({
        required yPlane,
        required uPlane,
        required vPlane,
        required yRowStride,
        required uvRowStride,
        required uvPixelStride,
        required width,
        required height,
      }) {
        if (_isPipelineBusy) return Future.value();
        _isPipelineBusy = true;

        // Aggressive safety timer: 80ms to prevent permanent freeze
        _safetyTimer?.cancel();
        _safetyTimer = Timer(const Duration(milliseconds: 80), () {
          _isPipelineBusy = false;
        });

        if (!encoderReady) {
          if (starting) return Future.value();
          starting = true;
          _appendLog('⚙ Cámara: ${width}x$height — iniciando encoder...');
          
          if (_socket != null) {
            final diagStr = "DIAGNOSTICS: width=$width, height=$height, "
                "yRowStride=$yRowStride, uvRowStride=$uvRowStride, "
                "uvPixelStride=$uvPixelStride";
            _socket!.add(_buildFrame(Uint8List.fromList(diagStr.codeUnits)));
          }

          _h264Encoder.start(
            width: width,
            height: height,
            fps: _quality.fps,
            bitrate: 2_000_000,
            onH264Chunk: (chunk) async {
              if (_socket != null) {
                try {
                  final frame = _buildFrame(chunk);
                  _socket!.add(frame);
                  
                  // Fire-and-forget flush: don't block the pipeline!
                  _socket!.flush().catchError((_) {});
                  
                  // Update counters without setState (stats timer handles display)
                  _framesSent++;
                  _bytesSent += frame.length;
                } catch (_) {}
              }
              _safetyTimer?.cancel();
              _isPipelineBusy = false;
            },
          ).then((_) {
            encoderReady = true;
            _appendLog('✓ Encoder listo');
          });
          
          return Future.value();
        }

        if (!_h264Encoder.isRunning || !_streaming) {
          _safetyTimer?.cancel();
          _isPipelineBusy = false;
          return Future.value();
        }

        _h264Encoder.pushYuvFrame(
          yPlane: yPlane,
          uPlane: uPlane,
          vPlane: vPlane,
          yRowStride: yRowStride,
          uvRowStride: uvRowStride,
          uvPixelStride: uvPixelStride,
          width: width,
          height: height,
        );

        return Future.value();
      });
    } else {
      await _cam.startStreaming(_onJpegFrame);
    }
  }

  Future<void> _stopStreaming() async {
    await _cam.stopStreaming();
    if (_useH264) await _h264Encoder.stop();
    _safetyTimer?.cancel();
    _dimTimer?.cancel();
    _isPipelineBusy = false;
    if (mounted) setState(() {
      _streaming = false;
      _previewOpacity = 1.0;
    });
    _appendLog('■ Streaming detenido');
  }

  void _onJpegFrame(Uint8List jpeg) {
    if (_socket == null) return;
    try {
      final frame = _buildFrame(jpeg);
      _socket!.add(frame);
      // Update counters without setState
      _framesSent++;
      _bytesSent += frame.length;
    } catch (_) {}
  }

  // ---- Socket ----------------------------------------------------------------

  Future<void> _connect() async {
    final ip   = _ipCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8080;
    if (ip.isEmpty) { _appendLog('⚠ Ingresa la IP del PC'); return; }

    setState(() {
      _status = AppStatus.connecting;
      _statusMsg = 'Conectando...';
      _framesSent = 0;
      _bytesSent  = 0;
      _displayFrames = 0;
      _displayBytes = 0;
      _currentFps = 0;
      _lastFpsFrames = 0;
    });
    _appendLog('→ Conectando a $ip:$port ...');
    await _savePrefs();

    try {
      _socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 5));
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      _socket!.listen(
        (_) {},
        onError: (_) => _onDisconnect(),
        onDone:  ()  => _onDisconnect(),
        cancelOnError: true,
      );
      setState(() {
        _status    = AppStatus.connected;
        _statusMsg = 'Conectado a $ip:$port';
      });
      _appendLog('✓ Conexión establecida');
      WakelockPlus.enable();
    } on SocketException catch (e) {
      setState(() {
        _status    = AppStatus.error;
        _statusMsg = 'Error: ${e.message}';
      });
      _appendLog('✗ ${e.message}');
    }
  }

  void _disconnect({bool silent = false}) {
    _stopStreaming();
    _socket?.destroy();
    _socket = null;
    WakelockPlus.disable();
    if (!silent && mounted) _onDisconnect();
  }

  void _onDisconnect() {
    if (!mounted) return;
    setState(() {
      _status    = AppStatus.idle;
      _statusMsg = 'Desconectado';
      _streaming = false;
    });
  }

  // ---- Frame protocol --------------------------------------------------------

  Uint8List _buildFrame(Uint8List payload) {
    final buf = ByteData(8 + payload.length);
    buf.setUint32(0, _magic, Endian.little);
    buf.setUint32(4, payload.length, Endian.little);
    final out = buf.buffer.asUint8List();
    out.setRange(8, 8 + payload.length, payload);
    return out;
  }

  // ---- Prefs / IP ------------------------------------------------------------

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final ip   = p.getString('last_ip');
    final port = p.getString('last_port');
    if (ip   != null && mounted) _ipCtrl.text   = ip;
    if (port != null && mounted) _portCtrl.text = port;
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('last_ip',   _ipCtrl.text);
    await p.setString('last_port', _portCtrl.text);
  }

  Future<void> _fetchLocalIp() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      if (mounted) setState(() => _localIp = ip ?? 'No disponible');
    } catch (_) {
      if (mounted) setState(() => _localIp = 'Error');
    }
  }

  void _appendLog(String msg) {
    final now = DateTime.now();
    final ts  = '${now.hour.toString().padLeft(2,'0')}:'
                '${now.minute.toString().padLeft(2,'0')}:'
                '${now.second.toString().padLeft(2,'0')}';
    _log.add('[$ts] $msg');
    if (_log.length > 80) _log.removeAt(0);
  }

  // ============================================================
  //  Settings Popup
  // ============================================================

  void _showSettingsPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettingsSheet(
        ipCtrl: _ipCtrl,
        portCtrl: _portCtrl,
        localIp: _localIp,
        quality: _quality,
        useH264: _useH264,
        status: _status,
        streaming: _streaming,
        log: _log,
        onQualityChanged: (q) async {
          setState(() => _quality = q);
          await _cam.setQuality(q);
          _appendLog('⚙ Calidad: ${q.label} (${q.targetWidth}p, ${q.fps}fps)');
        },
        onCodecChanged: (val) async {
          setState(() => _useH264 = val);
          _appendLog('⚙ Codec: ${val ? "H.264" : "JPEG"} — reiniciando cámara...');
          setState(() => _cameraReady = false);
          await _initCamera();
        },
        onClearLog: () => setState(() => _log.clear()),
        onRefreshIp: _fetchLocalIp,
      ),
    );
  }

  // ============================================================
  //  UI — Fullscreen camera with overlays
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _resetDimTimer,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Layer 1: Camera preview (fullscreen) ──
            if (_cameraReady && _cam.controller != null)
              AnimatedOpacity(
                opacity: _previewOpacity,
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOut,
                child: SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _cam.controller!.value.previewSize?.height ?? 1280,
                      height: _cam.controller!.value.previewSize?.width ?? 720,
                      child: CameraPreview(_cam.controller!),
                    ),
                  ),
                ),
              )
            else if (_cameraError != null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Color(0xFFFF3D5E), size: 60),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(_cameraError!,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                      onPressed: _initCamera,
                    ),
                  ],
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
              ),

            // ── Layer 2: Dimmed overlay text ──
            if (_previewOpacity < 1.0)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app,
                        color: Colors.white.withOpacity(0.3), size: 48),
                    const SizedBox(height: 8),
                    Text('Toca para ver preview',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 14)),
                  ],
                ),
              ),

            // ── Layer 3: Top overlay — status + settings ──
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  // Status badge
                  _buildStatusBadge(),
                  const SizedBox(width: 8),
                  // FPS counter
                  if (_streaming)
                    _buildFpsBadge(),
                  const Spacer(),
                  // Settings button
                  _overlayButton(
                    icon: Icons.settings,
                    onTap: _showSettingsPopup,
                  ),
                  const SizedBox(width: 8),
                  // Switch camera
                  _overlayButton(
                    icon: Icons.flip_camera_android,
                    onTap: () async {
                      await _cam.switchCamera();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),

            // ── Layer 4: Bottom action bar ──
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              child: _buildBottomBar(),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Overlay widgets -------------------------------------------------------

  Widget _buildStatusBadge() {
    final isLive = _streaming;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isLive
            ? Colors.red.withOpacity(0.85)
            : Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLive ? Colors.red : Colors.white24,
          width: 1,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (isLive) ...[
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text('LIVE',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5)),
        ] else ...[
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _statusColor(),
            ),
          ),
          const SizedBox(width: 6),
          Text(_status == AppStatus.connected ? 'Conectado' : 'Offline',
              style: TextStyle(
                  color: _statusColor(),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }

  Widget _buildFpsBadge() {
    final color = _currentFps >= 20
        ? const Color(0xFF00E676)
        : _currentFps >= 10
            ? const Color(0xFFFFC107)
            : const Color(0xFFFF5252);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$_currentFps',
            style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
        const SizedBox(width: 3),
        Text('FPS',
            style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          // Stats
          if (_streaming) ...[
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_displayFrames frames',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 10)),
                  Text(_fmtBytes(_displayBytes),
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 10)),
                ],
              ),
            ),
          ],
          const Spacer(),
          // Main action button
          _buildMainActionButton(),
          const Spacer(),
          // Streaming toggle (only when connected)
          if (_status == AppStatus.connected)
            _buildStreamButton()
          else
            const SizedBox(width: 56),
        ],
      ),
    );
  }

  Widget _buildMainActionButton() {
    final isConn = _status == AppStatus.connected;
    final isConnecting = _status == AppStatus.connecting;

    return GestureDetector(
      onTap: isConnecting
          ? null
          : isConn
              ? () => _disconnect()
              : _connect,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isConn
                ? [const Color(0xFFFF3D5E), const Color(0xFFFF6B6B)]
                : isConnecting
                    ? [const Color(0xFFFFC107), const Color(0xFFFFD54F)]
                    : [const Color(0xFF00E5FF), const Color(0xFF00B8D4)],
          ),
          boxShadow: [
            BoxShadow(
              color: (isConn
                      ? const Color(0xFFFF3D5E)
                      : const Color(0xFF00E5FF))
                  .withOpacity(0.4),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          isConn
              ? Icons.link_off
              : isConnecting
                  ? Icons.hourglass_top
                  : Icons.link,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildStreamButton() {
    return GestureDetector(
      onTap: _streaming ? _stopStreaming : _startStreaming,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _streaming
              ? const Color(0xFFFF6D00).withOpacity(0.85)
              : const Color(0xFF00E676).withOpacity(0.85),
          border: Border.all(
            color: _streaming
                ? const Color(0xFFFF6D00)
                : const Color(0xFF00E676),
            width: 2,
          ),
        ),
        child: Icon(
          _streaming ? Icons.stop_rounded : Icons.videocam,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _overlayButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  // ---- Shared helpers --------------------------------------------------------

  Color _statusColor() => switch (_status) {
        AppStatus.idle       => Colors.white38,
        AppStatus.connecting => const Color(0xFFFFC107),
        AppStatus.connected  => const Color(0xFF00E5FF),
        AppStatus.error      => const Color(0xFFFF3D5E),
      };

  String _fmtBytes(int b) {
    if (b < 1024)         return '${b}B';
    if (b < 1024 * 1024)  return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)}MB';
  }
}

// ============================================================
//  Settings Bottom Sheet — Glassmorphism popup
// ============================================================

class _SettingsSheet extends StatefulWidget {
  final TextEditingController ipCtrl;
  final TextEditingController portCtrl;
  final String? localIp;
  final StreamQuality quality;
  final bool useH264;
  final AppStatus status;
  final bool streaming;
  final List<String> log;
  final Future<void> Function(StreamQuality) onQualityChanged;
  final Future<void> Function(bool) onCodecChanged;
  final VoidCallback onClearLog;
  final VoidCallback onRefreshIp;

  const _SettingsSheet({
    required this.ipCtrl,
    required this.portCtrl,
    required this.localIp,
    required this.quality,
    required this.useH264,
    required this.status,
    required this.streaming,
    required this.log,
    required this.onQualityChanged,
    required this.onCodecChanged,
    required this.onClearLog,
    required this.onRefreshIp,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late StreamQuality _quality;
  late bool _useH264;
  bool _showLog = false;

  @override
  void initState() {
    super.initState();
    _quality = widget.quality;
    _useH264 = widget.useH264;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.only(top: 80),
      padding: EdgeInsets.only(bottom: bottomPad),
      decoration: const BoxDecoration(
        color: Color(0xF0111827),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF00E5FF), width: 1),
          left: BorderSide(color: Color(0xFF1E2D40), width: 0.5),
          right: BorderSide(color: Color(0xFF1E2D40), width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            const Row(
              children: [
                Icon(Icons.tune, color: Color(0xFF00E5FF), size: 20),
                SizedBox(width: 8),
                Text('Configuración',
                    style: TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 20),

            // Server connection
            _sectionTitle('Servidor PC'),
            const SizedBox(height: 8),
            _inputField(widget.ipCtrl, 'IP del servidor', Icons.computer,
                enabled: widget.status != AppStatus.connected),
            const SizedBox(height: 8),
            _inputField(widget.portCtrl, 'Puerto', Icons.settings_ethernet,
                enabled: widget.status != AppStatus.connected),
            const SizedBox(height: 16),

            // Device IP
            _sectionTitle('Dispositivo'),
            const SizedBox(height: 8),
            _infoRow(Icons.wifi, 'IP local',
                widget.localIp ?? 'Detectando...', widget.onRefreshIp),
            const SizedBox(height: 16),

            // Quality selector
            _sectionTitle('Calidad de Stream'),
            const SizedBox(height: 10),
            Row(
              children: StreamQuality.values.map((q) {
                final selected = q == _quality;
                return Expanded(
                  child: GestureDetector(
                    onTap: widget.streaming
                        ? null
                        : () {
                            setState(() => _quality = q);
                            widget.onQualityChanged(q);
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFF1A2332),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFF2A3A4E),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(q.label,
                              style: TextStyle(
                                  color: selected ? Colors.black : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text('${q.targetWidth}p · ${q.fps}fps',
                              style: TextStyle(
                                  color: selected
                                      ? Colors.black54
                                      : Colors.white38,
                                  fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Codec toggle
            _sectionTitle('Codec'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2332),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A3A4E)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.memory, color: Color(0xFF00E5FF), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        _useH264
                            ? 'H.264 Hardware (Recomendado)'
                            : 'JPEG Software',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                  ),
                  Switch(
                    value: _useH264,
                    activeColor: const Color(0xFF00E5FF),
                    onChanged: widget.streaming
                        ? null
                        : (val) {
                            setState(() => _useH264 = val);
                            widget.onCodecChanged(val);
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Log section (collapsible)
            GestureDetector(
              onTap: () => setState(() => _showLog = !_showLog),
              child: Row(
                children: [
                  Icon(Icons.terminal,
                      color: const Color(0xFF00E5FF).withOpacity(0.7),
                      size: 16),
                  const SizedBox(width: 6),
                  Text('Registro de actividad',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Icon(
                    _showLog
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white30,
                    size: 20,
                  ),
                ],
              ),
            ),
            if (_showLog) ...[
              const SizedBox(height: 8),
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E2D40)),
                ),
                padding: const EdgeInsets.all(8),
                child: widget.log.isEmpty
                    ? Center(
                        child: Text('Sin actividad',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.2),
                                fontSize: 11)))
                    : ListView.builder(
                        reverse: true,
                        itemCount: widget.log.length,
                        itemBuilder: (_, i) {
                          final line = widget.log[widget.log.length - 1 - i];
                          return Text(line,
                              style: TextStyle(
                                color: line.contains('✓')
                                    ? const Color(0xFF00E5FF)
                                    : line.contains('✗') ||
                                            line.contains('⚠')
                                        ? const Color(0xFFFF3D5E)
                                        : Colors.white54,
                                fontSize: 10,
                                height: 1.5,
                                fontFamily: 'monospace',
                              ));
                        },
                      ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onClearLog,
                  child: Text('Limpiar',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 11)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text,
        style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2));
  }

  Widget _inputField(TextEditingController c, String hint, IconData icon,
      {bool enabled = true}) {
    return TextField(
      controller: c,
      enabled: enabled,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon:
            Icon(icon, size: 18, color: const Color(0xFF00E5FF)),
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF1A2332),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A3A4E))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A3A4E))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xFF00E5FF), width: 1.5)),
        disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1A2332))),
      ),
    );
  }

  Widget _infoRow(
      IconData icon, String label, String value, VoidCallback onRefresh) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3A4E)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00E5FF), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4), fontSize: 10)),
                Text(value,
                    style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRefresh,
            child:
                const Icon(Icons.refresh, color: Colors.white30, size: 18),
          ),
        ],
      ),
    );
  }
}
