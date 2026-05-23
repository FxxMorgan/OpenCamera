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
  bool       _settingsOpen = true;
  bool       _isPortrait = true;
  bool       _showLog = false;

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
  bool  _useNativePreview = false;
  int?  _nativeTextureId;
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
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      if (_streaming && _useH264) {
        final stats = await _h264Encoder.getStats();
        if (!mounted) return;
        setState(() {
          _currentFps = stats['fps']?.round() ?? 0;
          _displayBytes = stats['bytesSent'] ?? 0;
          // Synchronize native connection status back to AppStatus
          final connected = stats['isConnected'] as bool? ?? false;
          if (connected) {
            _status = AppStatus.connected;
            _statusMsg = 'Conectado (H.264)';
          } else {
            _status = AppStatus.connecting;
            _statusMsg = 'Reconectando socket...';
          }
        });
      } else {
        final fps = _framesSent - _lastFpsFrames;
        _lastFpsFrames = _framesSent;
        setState(() {
          _currentFps = fps;
          _displayFrames = _framesSent;
          _displayBytes = _bytesSent;
        });
      }
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

  Future<void> _switchCamera() async {
    if (!_cameraReady) return;

    final wasStreaming = _streaming;
    _appendLog('⚙ Cambiando de cámara...');

    if (_useH264) {
      // 1. Si está transmitiendo, detiene el encoder nativo primero
      if (wasStreaming) {
        await _h264Encoder.stop();
      }

      // 2. Liberar cámara de Flutter
      await _cam.dispose();

      // 3. Obtener el siguiente índice de cámara
      final nextIndex = (_cam.selectedIndex + 1) % _cam.cameras.length;

      if (wasStreaming) {
        // Inicializa el CameraService en Flutter con el nuevo índice para actualizar el estado,
        // luego libéralo inmediatamente para que la capa Kotlin nativa pueda usarlo.
        await _cam.initializeCamera(cameraIndex: nextIndex, quality: _quality, useYuv: _useH264);
        await _cam.dispose();

        // 4. Crear textura nativa
        final textureId = await _h264Encoder.createTexture();
        if (textureId == null) {
          _appendLog('⚠ Error al crear textura nativa');
          await _initCamera();
          return;
        }

        final ip = _ipCtrl.text.trim();
        final port = int.tryParse(_portCtrl.text.trim()) ?? 8080;
        final width = _isPortrait ? (_quality.targetWidth * 9) ~/ 16 : _quality.targetWidth;
        final height = _isPortrait ? _quality.targetWidth : (_quality.targetWidth * 9) ~/ 16;
        final cameraId = _cam.cameras[nextIndex].name;

        // 5. Iniciar motor nativo H.264 con la nueva cámara
        final success = await _h264Encoder.start(
          width: width,
          height: height,
          fps: _quality.fps,
          bitrate: 2000000,
          serverIp: ip,
          serverPort: port,
          cameraId: cameraId,
          textureId: textureId,
        );

        if (success) {
          setState(() {
            _nativeTextureId = textureId;
            _useNativePreview = true;
            _cameraReady = true;
            _streaming = true;
          });
          _appendLog('✓ Streaming H.264 cambiado a cámara frontal/trasera ($cameraId)');
        } else {
          _appendLog('⚠ Falló reinicio de streaming con cámara $cameraId');
          await _h264Encoder.stop();
          await _initCamera();
        }
      } else {
        // Si no estaba transmitiendo, simplemente re-inicializa en Flutter para la vista previa
        setState(() => _cameraReady = false);
        await _cam.initializeCamera(cameraIndex: nextIndex, quality: _quality, useYuv: _useH264);
        setState(() {
          _cameraReady = true;
        });
      }
    } else {
      // Modo JPEG normal
      setState(() => _cameraReady = false);
      await _cam.switchCamera();
      setState(() {
        _cameraReady = true;
        _streaming = _cam.isStreaming;
      });
    }
  }

  Future<void> _startStreaming() async {
    if (!_cameraReady || (_socket == null && !_useH264)) return;
    
    _resetDimTimer();

    if (_useH264) {
      _appendLog('⚙ Iniciando pipeline H.264 Zero-Copy nativo...');
      setState(() {
        _cameraReady = false;
        _streaming = true;
      });
      
      // 1. Liberar cámara de Flutter para poder abrirla nativamente en Kotlin
      await _cam.dispose();

      // 2. Crear textura nativa para previsualización
      final textureId = await _h264Encoder.createTexture();
      if (textureId == null) {
        _appendLog('⚠ Error al crear textura nativa');
        await _initCamera();
        return;
      }

      final cameraId = _cam.cameras.isNotEmpty
          ? _cam.cameras[_cam.selectedIndex].name
          : '0';

      final ip = _ipCtrl.text.trim();
      final port = int.tryParse(_portCtrl.text.trim()) ?? 8080;
      final width = _isPortrait ? (_quality.targetWidth * 9) ~/ 16 : _quality.targetWidth;
      final height = _isPortrait ? _quality.targetWidth : (_quality.targetWidth * 9) ~/ 16;

      // 3. Iniciar motor nativo H.264
      final success = await _h264Encoder.start(
        width: width,
        height: height,
        fps: _quality.fps,
        bitrate: 2000000,
        serverIp: ip,
        serverPort: port,
        cameraId: cameraId,
        textureId: textureId,
      );

      if (success) {
        if (mounted) setState(() {
          _nativeTextureId = textureId;
          _useNativePreview = true;
          _cameraReady = true;
        });
        _appendLog('✓ Streaming H.264 nativo a 30 FPS iniciado');
      } else {
        _appendLog('⚠ Falló inicio de streaming nativo');
        await _h264Encoder.stop();
        await _initCamera();
      }
    } else {
      // Modo JPEG normal
      setState(() => _streaming = true);
      _appendLog('▶ Streaming JPEG iniciado (${_quality.label})');
      await _cam.startStreaming(_onJpegFrame);
    }
  }

  Future<void> _stopStreaming() async {
    _safetyTimer?.cancel();
    _dimTimer?.cancel();
    _isPipelineBusy = false;
    
    if (_useH264) {
      await _h264Encoder.stop();
      if (mounted) setState(() {
        _useNativePreview = false;
        _nativeTextureId = null;
        _streaming = false;
        _cameraReady = false;
        _previewOpacity = 1.0;
      });
      _appendLog('■ Streaming H.264 detenido, restaurando previsualización...');
      await _initCamera(); // Restaurar cámara normal
    } else {
      await _cam.stopStreaming();
      if (mounted) setState(() {
        _streaming = false;
        _previewOpacity = 1.0;
      });
      _appendLog('■ Streaming JPEG detenido');
    }
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

    if (_useH264) {
      // En modo H.264, la conexión TCP se maneja nativamente en Kotlin.
      // Simulamos que estamos conectados y llamamos a startStreaming.
      setState(() {
        _status    = AppStatus.connected;
        _statusMsg = 'Conectado a $ip:$port';
      });
      _appendLog('✓ Conexión nativa inicializada');
      WakelockPlus.enable();
      await _startStreaming();
    } else {
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
        _appendLog('✓ Conexión establecida (JPEG)');
        WakelockPlus.enable();
        await _startStreaming();
      } on SocketException catch (e) {
        setState(() {
          _status    = AppStatus.error;
          _statusMsg = 'Error: ${e.message}';
        });
        _appendLog('✗ ${e.message}');
      }
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
      _settingsOpen = true;
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
    setState(() => _settingsOpen = true);
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
            // ── Layer 1: Camera preview (fullscreen) with RepaintBoundary ──
            if (_cameraReady && (_useNativePreview ? _nativeTextureId != null : _cam.controller != null))
              Visibility(
                visible: !_settingsOpen,
                maintainState: true,
                child: RepaintBoundary(
                  child: AnimatedOpacity(
                    opacity: _previewOpacity,
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOut,
                    child: SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          // Native preview: SurfaceTexture transform always rotates content
                          // to portrait when the phone is locked to portrait, so always use
                          // portrait dimensions (width < height) regardless of _isPortrait.
                          // Flutter CameraPreview: use orientation-dependent dimensions.
                          width: _useNativePreview
                              ? (_quality.targetWidth * 9 / 16)
                              : (_isPortrait
                                  ? (_cam.controller?.value.previewSize?.height ?? 720).toDouble()
                                  : (_cam.controller?.value.previewSize?.width ?? 1280).toDouble()),
                          height: _useNativePreview
                              ? _quality.targetWidth.toDouble()
                              : (_isPortrait
                                  ? (_cam.controller?.value.previewSize?.width ?? 1280).toDouble()
                                  : (_cam.controller?.value.previewSize?.height ?? 720).toDouble()),
                          child: _useNativePreview && _nativeTextureId != null
                              ? Texture(textureId: _nativeTextureId!)
                              : CameraPreview(_cam.controller!),
                        ),
                      ),
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

            // ── Layer 3: Top header bar (Ultra Premium High-Contrast Bar) ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: RepaintBoundary(
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                      16, MediaQuery.of(context).padding.top + 12, 16, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xEC0A0E1A), // Solid dark premium navy
                    border: const Border(
                      bottom: BorderSide(
                        color: Color(0xFF00E5FF), // Thin bright neon cyan bottom border
                        width: 1.5,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withOpacity(0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
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
                        onTap: _switchCamera,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Layer 4: Bottom action bar ──
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              child: RepaintBoundary(
                child: _buildBottomBar(),
              ),
            ),

            // ── Layer 5: Settings Drawer ──
            if (_settingsOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _settingsOpen = false),
                  child: Container(color: Colors.black.withOpacity(0.6)),
                ),
              ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              bottom: _settingsOpen ? 0 : -MediaQuery.of(context).size.height,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.85,
                decoration: const BoxDecoration(
                  color: Color(0xFF0B101A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: Color(0xFF00E5FF), width: 2),
                  ),
                ),
                child: Column(
                  children: [
                    // ── Header ──
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.tune, color: Color(0xFF00E5FF), size: 24),
                          const SizedBox(width: 8),
                          const Text(
                            'Configuración',
                            style: TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => setState(() => _settingsOpen = false),
                          ),
                        ],
                      ),
                    ),
                    
                    // ── Divider ──
                    const Divider(color: Color(0xFF1E2D40), height: 1),
                    
                    // ── Scrollable content ──
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        children: [
                          // IP
                          _buildSettingsLabel('Servidor PC'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _ipCtrl,
                            enabled: _status != AppStatus.connected,
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration('IP del servidor', Icons.computer),
                          ),
                          const SizedBox(height: 12),
                          
                          // Port
                          TextField(
                            controller: _portCtrl,
                            enabled: _status != AppStatus.connected,
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration('Puerto', Icons.settings_ethernet),
                          ),
                          const SizedBox(height: 16),
                          
                          // Connect button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _status == AppStatus.connected
                                    ? const Color(0xFFFF3D5E)
                                    : const Color(0xFF00E5FF),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: Icon(_status == AppStatus.connected ? Icons.link_off : Icons.link),
                              label: Text(
                                _status == AppStatus.connected
                                    ? 'DESCONECTAR'
                                    : _status == AppStatus.connecting
                                        ? 'CONECTANDO...'
                                        : 'CONECTAR AHORA',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                              ),
                              onPressed: _status == AppStatus.connecting
                                  ? null
                                  : () {
                                      setState(() => _settingsOpen = false);
                                      if (_status == AppStatus.connected) {
                                        _disconnect();
                                      } else {
                                        _connect();
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Device IP
                          _buildSettingsLabel('Dispositivo'),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2332),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF2A3A4E)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.wifi, color: Color(0xFF00E5FF), size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('IP local', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
                                      Text(_localIp ?? 'Detectando...', style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 14, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _fetchLocalIp,
                                  child: const Icon(Icons.refresh, color: Colors.white30, size: 18),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Quality
                          _buildSettingsLabel('Calidad de Stream'),
                          const SizedBox(height: 10),
                          Row(
                            children: StreamQuality.values.map((q) {
                              final selected = q == _quality;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: _streaming ? null : () async {
                                    setState(() => _quality = q);
                                    await _cam.setQuality(q);
                                    _appendLog('⚙ Calidad: ${q.label} (${q.targetWidth}p, ${q.fps}fps)');
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: selected ? const Color(0xFF00E5FF) : const Color(0xFF1A2332),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: selected ? const Color(0xFF00E5FF) : const Color(0xFF2A3A4E)),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(q.label, style: TextStyle(color: selected ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text('${q.targetWidth}p · ${q.fps}fps', style: TextStyle(color: selected ? Colors.black54 : Colors.white38, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                          
                          // Codec
                          _buildSettingsLabel('Codec'),
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
                                    _useH264 ? 'H.264 Hardware (Recomendado)' : 'JPEG Software',
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                ),
                                Switch(
                                  value: _useH264,
                                  activeColor: const Color(0xFF00E5FF),
                                  onChanged: _streaming ? null : (val) async {
                                    setState(() => _useH264 = val);
                                    _appendLog('⚙ Codec: ${val ? "H.264" : "JPEG"} — reiniciando...');
                                    setState(() => _cameraReady = false);
                                    await _initCamera();
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Orientation
                          _buildSettingsLabel('Orientación del Stream'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _buildOrientationBtn('Vertical', Icons.stay_current_portrait, true),
                              _buildOrientationBtn('Horizontal', Icons.stay_current_landscape, false),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
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
                              child: _log.isEmpty
                                  ? Center(
                                      child: Text('Sin actividad',
                                          style: TextStyle(
                                              color: Colors.white.withOpacity(0.5),
                                              fontSize: 11)))
                                  : ListView.builder(
                                      reverse: true,
                                      itemCount: _log.length,
                                      itemBuilder: (_, i) {
                                        final line = _log[_log.length - 1 - i];
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
                                onPressed: () => setState(() => _log.clear()),
                                child: Text('Limpiar',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.3),
                                        fontSize: 11)),
                              ),
                            ),
                          ],
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withOpacity(0.7),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: const Color(0xFF00E5FF)),
      hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF1A2332),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2A3A4E)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2A3A4E)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1A2332)),
      ),
    );
  }

  Widget _buildOrientationBtn(String label, IconData icon, bool portrait) {
    final selected = _isPortrait == portrait;
    return Expanded(
      child: GestureDetector(
        onTap: _streaming ? null : () => setState(() => _isPortrait = portrait),
        child: Container(
          margin: EdgeInsets.only(right: portrait ? 4 : 0, left: portrait ? 0 : 4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF00E5FF) : const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? const Color(0xFF00E5FF) : const Color(0xFF2A3A4E)),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? Colors.black : Colors.white70, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
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
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A), // Fully opaque dark premium navy background to prevent GPU alpha blending bugs
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF00E5FF), // High-visibility neon cyan border
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withOpacity(0.25), // High-contrast neon cyan glow
            blurRadius: 16,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Settings button or Stats
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
          ] else ...[
            // Beautiful settings button on the bottom bar for high visibility
            GestureDetector(
              onTap: _showSettingsPopup,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                ),
                child: const Icon(Icons.settings, color: Color(0xFF00E5FF), size: 20),
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
              : () {
                  final ip = _ipCtrl.text.trim();
                  if (ip.isNotEmpty && ip != '192.168.1.') {
                    _connect();
                  } else {
                    _showSettingsPopup();
                  }
                },
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
                  : Icons.power_settings_new, // Changed to power icon to indicate "Connect" instead of settings
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
