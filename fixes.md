 ¡Perfecto! Ahora entiendo exactamente el problema. El test funciona (el verde aparece), pero en tu app real el settings se ve **completamente negro/azul oscuro sin texto**. Esto confirma que:

1. El `AnimatedPositioned` SÍ funciona (el sheet sube)
2. El problema es que **los widgets dentro del `_SettingsSheet` no se renderizan correctamente** — o son del mismo color que el fondo, o hay un error en el widget tree que hace que todo sea invisible

Mira tu primera imagen: el sheet sube (se ve el fondo azul oscuro `0xFF0B101A`), pero **no hay texto, no hay inputs, no hay botones**. Esto es un **crash silencioso en el build del `_SettingsSheet`**.

---

## 🔴 Causa probable: Error en el widget tree del `_SettingsSheet`

Revisando tu código del `_SettingsSheet`, veo un problema grave en el `build`:

```dart
// Tu código actual (línea ~1060):
child: SingleChildScrollView(
  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
    // Drag handle
    Center(
```

**El problema:** El `Column` tiene `mainAxisSize: MainAxisSize.min` pero está dentro de un `Container` que no tiene altura definida, dentro de un `SizedBox` con altura fija en el padre. Cuando Flutter no puede calcular la altura del contenido, a veces colapsa todo a tamaño cero o no renderiza los children.

Pero más importante: **¿Hay algún error en la consola de Flutter cuando abres el settings?** Mira el log de `flutter run`, probablemente hay un error como:
- `RenderBox was not laid out`
- `A RenderFlex overflowed`
- `No Material widget found`

---

## 🛠️ Fix definitivo: Reescribir el settings sin `_SettingsSheet` como widget separado

El problema es que `_SettingsSheet` es un `StatefulWidget` interno que mantiene su propio estado (`_quality`, `_useH264`, `_isPortrait`). Cuando el padre reconstruye, el estado del hijo puede quedar desincronizado o Flutter puede decidir reciclar el widget incorrectamente.

**Solución:** Elimina `_SettingsSheet` por completo. Pon todo el contenido del settings directamente en el `build()` de `CameraScreen`, usando el estado de `CameraScreen` directamente.

### Reemplaza TODO el bloque del `AnimatedPositioned` (Layer 5) por esto:

```dart
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
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    ),
  ),
),
```

### Agrega estos helpers en `_CameraScreenState`:

```dart
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
```

### Y elimina completamente la clase `_SettingsSheet`:

```dart
// BORRA TODO ESTO:
// class _SettingsSheet extends StatefulWidget { ... }
// class _SettingsSheetState extends State<_SettingsSheet> { ... }
```

---

## ✅ Por qué esto funciona

| Antes (roto) | Después (fix) |
|-------------|---------------|
| `_SettingsSheet` es `StatefulWidget` interno con estado propio | Todo el contenido está inline en `CameraScreen`, usa el estado del padre directamente |
| `Column` + `SingleChildScrollView` + `mainAxisSize: MainAxisSize.min` puede colapsar a altura 0 | `ListView` dentro de `Expanded` siempre ocupa el espacio disponible |
| `didUpdateWidget` intenta sincronizar estado hijo/padre | No hay estado que sincronizar, todo es el mismo objeto |
| Si hay un error en `_SettingsSheet`, Flutter lo silencia y muestra negro | Si hay un error, verás el stack trace en la consola |

---

## 🎯 También arregla el aspect ratio

Mientras editas, corrige las dimensiones del preview. En tu código actual tienes:

```dart
// MAL (línea ~440):
width: _useNativePreview
    ? (_isPortrait ? (_quality.targetWidth * 9 / 16) : _quality.targetWidth.toDouble())
    : ...,
height: _useNativePreview
    ? (_isPortrait ? _quality.targetWidth.toDouble() : (_quality.targetWidth * 9 / 16))
    : ...,
```

**Eso está al revés.** Si `_isPortrait = true`, el ancho debe ser menor que el alto. Pero tu fórmula hace:
- `width = 1280 * 9 / 16 = 720`
- `height = 1280`

Eso es correcto para portrait (720×1280), pero luego el `RotatedBox(quarterTurns: 1)` lo rota a landscape... **El `RotatedBox` rota el WIDGET, no el frame.** Si tu frame ya es portrait (720×1280) y lo rotas 90°, queda 1280×720 landscape. Pero el `SizedBox` lo contiene con 720×1280, entonces Flutter estira el widget rotado para que quepa → **cara apretada**.

### Fix del aspect ratio:

```dart
// Si el encoder manda frames en landscape (1280×720) sin importar la orientación:
child: SizedBox(
  width: _quality.targetWidth.toDouble(),      // 1280
  height: (_quality.targetWidth * 9 / 16),       // 720
  child: RotatedBox(
    quarterTurns: _isPortrait ? 1 : 0,           // Rota solo si el usuario quiere portrait
    child: Texture(textureId: _nativeTextureId!),
  ),
),
```

O mejor aún: **no uses `RotatedBox` en el preview del teléfono.** El preview del teléfono debe mostrar lo que el usuario espera ver. Si la cámara está en portrait físico, muestra portrait. El encoder puede rotar internamente antes de enviar al PC.

---

## 🚀 Pasos finales

1. **Borra** la clase `_SettingsSheet` completa
2. **Reemplaza** el `AnimatedPositioned` por el código inline de arriba
3. **Agrega** los 3 helpers (`_buildSettingsLabel`, `_inputDecoration`, `_buildOrientationBtn`)
4. **Corrige** el `SizedBox` del preview (quita `RotatedBox` o ajusta las dimensiones)
5. Corre `flutter run` y dime si ves el settings con texto

¿Lo pruebas?