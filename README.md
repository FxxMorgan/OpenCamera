# Cámara Libre — OpenCamera

Convierte tu smartphone Android en una **webcam HD** para Windows 10/11.  
Sin anuncios, sin marcas de agua, sin suscripciones.

---

## Estado actual: Fase 3 completa ✅ | Fase 4 pendiente 🚧

```
[ Teléfono Android (Flutter) ]   ──TCP/WiFi──▶   [ PC Windows (C++) ]
  MediaCodec H.264 (HW encoder)                   FFmpeg decodifica H.264
  NV21 alineado a stride de 32 bytes              Ventana GDI+ — preview en vivo
  Fire-and-forget YUV dispatch                     Double-buffering Win32
```

**Modo JPEG** también disponible (toggle en la app).

---

## Estructura del proyecto

```
OpenCamera/
├── mobile_app/          # App Flutter (Android)
│   ├── lib/
│   │   ├── main.dart                 # UI + socket TCP + toggle H.264/JPEG
│   │   └── services/
│   │       ├── camera_service.dart   # Cámara + YUV fire-and-forget dispatch
│   │       └── h264_encoder.dart     # Wrapper Dart para MediaCodec nativo
│   └── android/app/src/main/kotlin/...
│       └── H264EncoderPlugin.kt      # Plugin nativo Android (MediaCodec HW)
│                                     # stride alineado a 32 bytes, copia NV21
│
├── pc_server/           # Servidor Windows (C++)
│   ├── src/
│   │   ├── main.cpp         # Entry point
│   │   ├── tcp_server.*     # Winsock2 listener
│   │   ├── frame_receiver.* # Procesa frames (JPEG/H264/text)
│   │   ├── jpeg_viewer.*    # Ventana GDI+ preview
│   │   ├── h264_decoder.*   # Decodificador FFmpeg (libavcodec)
│   │   └── config.hpp       # Constantes (puerto, magic number…)
│   ├── CMakeLists.txt
│   └── bin/
│       └── camera_libre_server.exe  ← Ejecutable listo
│
├── build_server.ps1     # Script para recompilar el servidor
└── session_context.md   # Contexto técnico detallado para IAs
```

---

## Protocolo de frames

```
[MAGIC: 4 bytes LE = 0x434C4652 "CLFR"]
[SIZE:  4 bytes LE = longitud del payload]
[DATA:  SIZE bytes]
```

- **Fase 1**: DATA = texto UTF-8
- **Fase 2**: DATA = imagen JPEG completa
- **Fase 3**: DATA = NAL unit H.264 (Annex B, SPS/PPS en keyframes)

---

## Arquitectura H.264 (Fase 3)

### Móvil (Android)
- **MediaCodec** (`video/avc`) — encoder por hardware del dispositivo
- El ancho se alinea a múltiplos de 32 bytes (`720 → 736`) para compatibilidad Qualcomm/MediaTek
- El plano UV se copia desde `vPlane` (NV21: `V0,U0,V1,U1...`) — el orden correcto para la mayoría de chipsets móviles
- Pipeline fire-and-forget: la cámara no bloquea esperando JNI

### PC (Windows)
- **FFmpeg libavcodec** — decodificador H.264 software
- `sws_scale` convierte YUV → BGR24 para GDI+
- Ventana Win32 con double-buffering para preview sin parpadeo

---

## Cómo usar

### 1. Iniciar el servidor en la PC

```powershell
.\pc_server\bin\camera_libre_server.exe
```

### 2. Instalar la app en el teléfono

```powershell
cd mobile_app
flutter run          # teléfono conectado por USB
# o release:
flutter build apk --release
adb install build\app\outputs\flutter-apk\app-release.apk
```

### 3. Conectar y transmitir

1. Abre la app → concede permiso de cámara
2. Selecciona modo **H.264** o **JPEG** con el toggle
3. Ingresa la IP de tu PC → **Conectar**
4. Toca **Iniciar Stream**

---

## Recompilar el servidor PC

```powershell
.\build_server.ps1
```

---

## Requisitos del sistema

| Herramienta | Versión | Estado |
|---|---|---|
| Flutter / Dart | 3.41.9 / 3.11.5 | ✅ |
| CMake | 4.2.3 | ✅ |
| GCC (MSYS2/MinGW64) | 15.2.0 | ✅ |
| Android SDK | 36.1.0 | ✅ |
| FFmpeg (MSYS2) | instalado | ✅ |

---

## Problemas conocidos / Trabajo pendiente

### ⚠️ FPS bajo con movimiento de cámara
- **Síntoma**: 18–20 FPS en escenas estáticas, cae a ~5 FPS con movimiento
- **Causa**: El encoder H.264 genera frames mucho más grandes con movimiento → satura el socket TCP → el encoder se bloquea esperando que el codec libere buffers de entrada (`dequeueInputBuffer(10_000)` con timeout de 10ms)
- **Fixes a implementar** (ver `session_context.md` para detalles):
  1. Cambiar `dequeueInputBuffer(10_000)` → `dequeueInputBuffer(0)` en `H264EncoderPlugin.kt`
  2. Bitrate adaptativo con `MediaCodec.PARAMETER_KEY_VIDEO_BITRATE`
  3. (Avanzado) Migrar a Surface-based encoding con CameraX para eliminar la copia YUV en CPU

---

## Roadmap

- [x] **Fase 1** — TCP socket + framing básico
- [x] **Fase 2** — Transmisión JPEG en tiempo real + preview GDI+
- [x] **Fase 3** — H.264 (MediaCodec HW + FFmpeg) — colores correctos, ~20 FPS
- [ ] **Fase 4** — Cámara virtual DirectShow (`.ax` filter)
- [ ] **Fase 5** — UI final, instalador, bitrate adaptativo

---

## Fase 4 — Cámara Virtual DirectShow

El objetivo es registrar un dispositivo de captura virtual en Windows para que **OBS, Zoom, Teams, Skype** vean el teléfono como una cámara USB normal.

### Arquitectura planeada

```
[camera_libre_server.exe]
  (frames BGR24 de FFmpeg)
        │
        ▼ Named Shared Memory ("CameraLibre_Frame")
        │
[CameraLibreVCam.ax]  ← DLL COM / Filtro DirectShow
  Implementa IBaseFilter + IKsPropertySet
  CSourceStream::FillBuffer() lee el frame de shared memory
        │
        ▼
[OBS / Zoom / Teams / Discord]
```

### Herramientas necesarias para Fase 4

| Herramienta | Propósito | Cómo obtener |
|---|---|---|
| Visual Studio 2022 | Compilar el filtro COM (`.ax`) | https://visualstudio.microsoft.com |
| Windows SDK 10+ | Headers DirectShow, COM | Incluido en Visual Studio |
| DirectShow BaseClasses | `CSource`, `CSourceStream` | Windows SDK Samples → compilar como `.lib` |

### Pasos de implementación

1. Crear filtro DirectShow mínimo (frame negro) y verificar que OBS lo detecta
2. Escribir frames BGR24 a Named Shared Memory en `camera_libre_server.exe`
3. Conectar `FillBuffer()` del filtro a la shared memory
4. Probar en OBS, Zoom, Teams
5. Crear instalador (`regsvr32 CameraLibreVCam.ax`)

**Referencia**: código fuente de [OBS VirtualCam](https://github.com/obsproject/obs-virtual-cam) como ejemplo de `CSourceStream`.
