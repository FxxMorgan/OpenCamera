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
//  MainScreen — handles permissions then shows ConnectionScreen
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
    return const ConnectionScreen();
  }
}

// ============================================================
//  ConnectionScreen
// ============================================================

enum AppStatus { idle, connecting, connected, error }

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});
  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
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
  }

  @override
  void dispose() {
    _disconnect(silent: true);
    _safetyTimer?.cancel();
    _cam.dispose();
    _pulseCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  // ---- Camera ----------------------------------------------------------------

  Future<void> _initCamera() async {
    try {
      debugPrint('[Camera] Initializing cameras...');
      await _cam.initCameras();
      debugPrint('[Camera] Cameras found: ${_cam.cameras.length}');
      await _cam.initializeCamera(quality: _quality, useYuv: _useH264);
      debugPrint('[Camera] Camera initialized successfully (H.264: $_useH264)');
      if (mounted) setState(() {
        _cameraReady = true;
        _cameraError = null;
      });
    } catch (e, st) {
      debugPrint('[Camera] Init failed: $e\n$st');
      if (mounted) setState(() {
        _cameraReady = false;
        _cameraError = 'Error al inicializar cámara: $e';
      });
    }
  }

  Future<void> _startStreaming() async {
    if (!_cameraReady || _socket == null) return;
    setState(() => _streaming = true);
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
        if (_isPipelineBusy) {
          // Drop frame synchronously, releasing camera buffers immediately!
          return Future.value();
        }
        _isPipelineBusy = true;

        // Set safety timer: if no chunk is produced and network-flushed within 150ms,
        // reset the pipeline busy flag to prevent permanent freeze.
        _safetyTimer?.cancel();
        _safetyTimer = Timer(const Duration(milliseconds: 150), () {
          _isPipelineBusy = false;
        });

        if (!encoderReady) {
          if (starting) return Future.value(); // skip frames while starting
          starting = true;
          _appendLog('⚙ Cámara: ${width}x$height — iniciando encoder...');
          
          // Send diagnostics to the PC server via TCP!
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
                  
                  // Wait for the socket to physically flush the bytes over Wi-Fi!
                  // This provides genuine network-based backpressure.
                  await _socket!.flush();
                  
                  if (mounted) {
                    setState(() {
                      _framesSent++;
                      _bytesSent += frame.length;
                    });
                  }
                } catch (_) {}
              }
              // Reset pipeline busy state once network transmission is fully flushed!
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
    _isPipelineBusy = false;
    if (mounted) setState(() => _streaming = false);
    _appendLog('■ Streaming detenido');
  }

  void _onJpegFrame(Uint8List jpeg) {
    if (_socket == null) return;
    try {
      final frame = _buildFrame(jpeg);
      _socket!.add(frame);
      if (mounted) {
        setState(() {
          _framesSent++;
          _bytesSent += frame.length;
        });
      }
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
    if (!mounted) return;
    setState(() {
      final now = DateTime.now();
      final ts  = '${now.hour.toString().padLeft(2,'0')}:'
                  '${now.minute.toString().padLeft(2,'0')}:'
                  '${now.second.toString().padLeft(2,'0')}';
      _log.add('[$ts] $msg');
      if (_log.length > 80) _log.removeAt(0);
    });
  }

  // ============================================================
  //  UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _cameraReady
                  ? _buildMainLayout()
                  : _cameraError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Color(0xFFFF3D5E), size: 60),
                                const SizedBox(height: 20),
                                Text(_cameraError!,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00E5FF),
                                    foregroundColor: const Color(0xFF0A0E1A),
                                  ),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Reintentar'),
                                  onPressed: _initCamera,
                                ),
                              ],
                            ),
                          ),
                        )
                      : const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF00E5FF))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainLayout() {
    return Row(
      children: [
        // Left: camera preview (takes most space on wider screens)
        if (_cameraReady && _cam.controller != null)
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: OverflowBox(
                    maxWidth: double.infinity,
                    child: CameraPreview(_cam.controller!),
                  ),
                ),
                // Overlay: streaming badge
                if (_streaming)
                  Positioned(
                    top: 12, left: 12,
                    child: _liveBadge(),
                  ),
                // Overlay: quality selector
                Positioned(
                  bottom: 12, left: 0, right: 0,
                  child: _qualityBar(),
                ),
                // Switch camera button
                Positioned(
                  top: 12, right: 12,
                  child: _iconBtn(
                    Icons.flip_camera_android,
                    onTap: () async {
                      await _cam.switchCamera();
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
        // Right: control panel
        SizedBox(
          width: 220,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLocalIpCard(),
                const SizedBox(height: 8),
                _buildConnectionForm(),
                const SizedBox(height: 8),
                _buildStatusCard(),
                const SizedBox(height: 8),
                if (_status == AppStatus.connected) _buildStreamBtn(),
                const SizedBox(height: 8),
                if (_status == AppStatus.connected) _buildStatsRow(),
                const SizedBox(height: 8),
                _buildLog(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- Sub-widgets -----------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E2D40))),
      ),
      child: Row(
        children: [
          ScaleTransition(
            scale: _streaming ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusColor().withOpacity(0.15),
                border: Border.all(color: _statusColor(), width: 2),
              ),
              child: Icon(_statusIcon(), color: _statusColor(), size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Cámara Libre',
                style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1)),
          Text('Fase 3 — ${_useH264 ? "H.264" : "JPEG"} Stream',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 10)),
          ]),
          const Spacer(),
          // Toggle H.264 vs JPEG
          Row(
            children: [
              const Text('H.264', style: TextStyle(color: Colors.white70, fontSize: 10)),
              Switch(
                value: _useH264,
                activeColor: const Color(0xFF00E5FF),
                onChanged: _streaming ? null : (val) async {
                  setState(() => _useH264 = val);
                  _appendLog('⚙ Modo de códec cambiado a ${val ? "H.264" : "JPEG"} — reiniciando cámara...');
                  setState(() => _cameraReady = false);
                  await _initCamera();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocalIpCard() {
    return _glass(
      child: Row(children: [
        const Icon(Icons.wifi, color: Color(0xFF00E5FF), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('IP de este dispositivo',
                style: TextStyle(color: Colors.white38, fontSize: 9)),
            Text(_localIp ?? '...', style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 13,
                fontWeight: FontWeight.bold)),
          ]),
        ),
        GestureDetector(
          onTap: _fetchLocalIp,
          child: const Icon(Icons.refresh, color: Colors.white30, size: 16),
        ),
      ]),
    );
  }

  Widget _buildConnectionForm() {
    final isConn = _status == AppStatus.connected;
    return _glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('PC Servidor',
            style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 11,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _field(_ipCtrl,   'IP del PC',  '192.168.1.X', Icons.computer,          enabled: !isConn),
        const SizedBox(height: 6),
        _field(_portCtrl, 'Puerto',     '8080',         Icons.settings_ethernet, enabled: !isConn),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isConn ? const Color(0xFFFF3D5E) : const Color(0xFF00E5FF),
              foregroundColor: const Color(0xFF0A0E1A),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: Icon(isConn ? Icons.stop_circle : Icons.play_circle, size: 18),
            label: Text(isConn ? 'Desconectar' : 'Conectar',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            onPressed: _status == AppStatus.connecting
                ? null
                : isConn ? () => _disconnect() : _connect,
          ),
        ),
      ]),
    );
  }

  Widget _buildStatusCard() {
    return _glass(
      borderColor: _statusColor().withOpacity(0.35),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _statusColor(),
            boxShadow: [BoxShadow(
                color: _statusColor().withOpacity(0.7), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_statusMsg,
              style: TextStyle(
                  color: _statusColor(), fontSize: 11)),
        ),
      ]),
    );
  }

  Widget _buildStreamBtn() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _streaming
              ? const Color(0xFFFF6D00)
              : const Color(0xFF1DE9B6),
          foregroundColor: const Color(0xFF0A0E1A),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(
            _streaming ? Icons.videocam_off : Icons.videocam, size: 18),
        label: Text(
            _streaming ? 'Detener Stream' : 'Iniciar Stream',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold)),
        onPressed: _streaming ? _stopStreaming : _startStreaming,
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(children: [
      Expanded(child: _statCard(
          '${_framesSent}', 'frames', const Color(0xFF00E5FF))),
      const SizedBox(width: 6),
      Expanded(child: _statCard(
          _fmtBytes(_bytesSent), 'total', const Color(0xFF9C27B0))),
    ]);
  }

  Widget _statCard(String value, String label, Color color) {
    return _glass(
      child: Column(children: [
        Text(value, style: TextStyle(
            color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(
            color: Colors.white38, fontSize: 9)),
      ]),
    );
  }

  Widget _buildLog() {
    return _glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.terminal, color: Color(0xFF00E5FF), size: 12),
          const SizedBox(width: 4),
          const Text('Log', style: TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 10,
              fontWeight: FontWeight.bold)),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _log.clear()),
            child: const Text('limpiar',
                style: TextStyle(color: Colors.white24, fontSize: 9)),
          ),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 140,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.all(6),
            child: _log.isEmpty
                ? const Center(
                    child: Text('Sin actividad',
                        style: TextStyle(
                            color: Colors.white24, fontSize: 10)))
                : ListView.builder(
                    reverse: true,
                    itemCount: _log.length,
                    itemBuilder: (_, i) {
                      final line = _log[_log.length - 1 - i];
                      return Text(line,
                          style: TextStyle(
                            color: line.contains('✓')
                                ? const Color(0xFF00E5FF)
                                : line.contains('✗') || line.contains('⚠')
                                    ? const Color(0xFFFF3D5E)
                                    : Colors.white54,
                            fontSize: 9,
                            height: 1.5,
                            fontFamily: 'monospace',
                          ));
                    },
                  ),
          ),
        ),
      ]),
    );
  }

  // ---- Camera overlay widgets ------------------------------------------------

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 8)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 7, height: 7,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.white),
        ),
        const SizedBox(width: 4),
        const Text('LIVE',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5)),
      ]),
    );
  }

  Widget _qualityBar() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: StreamQuality.values.map((q) {
            final selected = q == _quality;
            return GestureDetector(
              onTap: () async {
                setState(() => _quality = q);
                await _cam.setQuality(q);
                _appendLog('⚙ Calidad: ${q.label} (${q.targetWidth}p, ${q.fps}fps)');
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF00E5FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(q.label,
                    style: TextStyle(
                        color: selected
                            ? const Color(0xFF0A0E1A)
                            : Colors.white70,
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  // ---- Shared ----------------------------------------------------------------

  Widget _glass({required Widget child, Color? borderColor}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: borderColor ?? const Color(0xFF1E2D40), width: 1),
      ),
      child: child,
    );
  }

  Widget _field(TextEditingController c, String label, String hint,
      IconData icon, {bool enabled = true}) {
    return TextField(
      controller: c,
      enabled: enabled,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white, fontSize: 11),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 14, color: const Color(0xFF00E5FF)),
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 10),
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
        filled: true,
        fillColor: const Color(0xFF0D1520),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: Color(0xFF1E2D40))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: Color(0xFF1E2D40))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide:
                const BorderSide(color: Color(0xFF00E5FF), width: 1.5)),
      ),
    );
  }

  Color _statusColor() => switch (_status) {
        AppStatus.idle       => Colors.white38,
        AppStatus.connecting => const Color(0xFFFFC107),
        AppStatus.connected  => const Color(0xFF00E5FF),
        AppStatus.error      => const Color(0xFFFF3D5E),
      };

  IconData _statusIcon() => switch (_status) {
        AppStatus.idle       => Icons.link_off,
        AppStatus.connecting => Icons.hourglass_top,
        AppStatus.connected  => _streaming ? Icons.videocam : Icons.link,
        AppStatus.error      => Icons.error_outline,
      };

  String _fmtBytes(int b) {
    if (b < 1024)         return '${b}B';
    if (b < 1024 * 1024)  return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)}MB';
  }
}
