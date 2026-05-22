# Contexto de Sesión — Cámara Libre (OpenCamera)

## Proyecto
**Ruta**: `d:\Programacion\OpenCamera`  
**Objetivo**: Convertir un smartphone Android en webcam HD para Windows vía WiFi (TCP).

---

## Arquitectura General

```
[ Teléfono Android (Flutter) ]  ──TCP──▶  [ PC Windows (C++ / MinGW) ]
  Captura cámara → MediaCodec H.264     Recibe → FFmpeg decodifica → muestra GDI+
  Fire-and-forget YUV dispatch           Ventana Win32 con double-buffering
```

**Protocolo de frame**: `[4 bytes MAGIC 0x434C4652][4 bytes SIZE little-endian][PAYLOAD]`

---

## Estado de las Fases

| Fase | Descripción | Estado |
|------|-------------|--------|
| 1 | TCP socket + framing básico | ✅ Completada |
| 2 | Streaming JPEG en tiempo real + GDI+ viewer | ✅ Completada y funcional |
| 3 | Codificación H.264 (MediaCodec nativo Android + FFmpeg PC) | ✅ Funcional con colores correctos, FPS parcialmente optimizado |
| 4 | Cámara virtual DirectShow | ❌ No iniciada |
| 5 | UI final, instalador | ❌ No iniciada |

---

## Cambios realizados en esta sesión (Depuración H.264)

### Problemas Resueltos

#### 1. 🛠️ Pérdida del Header SPS/PPS en Android
*   **Causa**: El flag `BUFFER_FLAG_CODEC_CONFIG` era descartado en `drainOutput`. Sin SPS/PPS, FFmpeg no podía inicializarse.
*   **Solución**: Extraer SPS/PPS directamente del buffer `CODEC_CONFIG` y anteponerlo a cada keyframe (IDR).

#### 2. ⚡ Sobrecarga del MethodChannel (rate limiting)
*   **Causa**: El callback `_onYuvFrame` bloqueaba el hilo de cámara con `await` hasta que el JNI `pushFrame` terminara, creando un pipeline secuencial (~5-8 FPS efectivos).
*   **Solución (actual)**: Fire-and-forget — el callback se llama sin await. La cola de Kotlin (max 5 frames con descarte) gestiona la presión de frames en el lado nativo.

#### 3. 🏎️ Cuello de botella en `copyYuvToBuffer`
*   **Causa**: Loop píxel por píxel (~460K llamadas JNI por frame) para el interleaving UV.
*   **Solución**: Copia masiva directa por fila con `buffer.put(array, offset, len)`.

#### 4. 📐 Stride/sliceHeight mismatch (líneas diagonales)
*   **Causa**: Los datos YUV se copiaban sin respetar el stride interno del codificador de hardware (Qualcomm requiere alineación a 32 bytes). Para `w=720`, el stride real es `736`.
*   **Solución**: `alignedWidth = (w + 31) and 31.inv()` — el codificador se inicializa con el ancho alineado y `copyYuvToBuffer` escribe a posiciones `y * stride`.

#### 5. 🎨 Colores invertidos (café→azul, NV21 vs NV12)
*   **Causa**: La cámara Android entrega `uPlane = [U0,V0,U1,V1,...]` (NV12) pero la mayoría de chipsets Qualcomm/MediaTek con `COLOR_FormatYUV420Flexible` esperan NV21 (V primero). Al copiar `uPlane` directamente, U y V se invertían.
*   **Solución**: Copiar desde `vPlane` en el caso `uvPixelStride == 2`. `vPlane` apunta al mismo buffer en memoria pero desplazado 1 byte, dando el orden `[V0,U0,V1,U1,...]` (NV21) que el codificador espera.

#### 6. 🧩 Fallo en el Scaler FFmpeg (`sws_getCachedContext`)
*   **Causa**: Se usaba `codecCtx_->pix_fmt` que vale `-1` hasta el primer frame decodificado.
*   **Solución**: Usar `frame_->format` (formato del frame decodificado real). Añadir `av_packet_unref` para evitar memory leak.

---

## Estado Actual del FPS y Latencia

### Síntomas Observados
- En escenas estáticas: **18–20 FPS** en modo High ✅
- Con movimiento de cámara: **baja a 5 FPS** ❌
- Latencia perceptible (~200–500ms) ❌

### Causa Raíz (Diagnóstico Técnico)

El problema con movimiento es **encodificación dependiente de bitrate + congestión de cola TCP**:

1.  **Encoder H.264 reacciona al movimiento con más bits**: Cuando la escena cambia rápido, el motor de compresión H.264 (macrobloques inter-frame) genera frames P y B mucho más grandes que en escenas estáticas. Un frame con movimiento puede pesar 5–10× más que uno estático.
2.  **TCP socket sin control de flujo explícito**: Los frames grandes saturan el socket TCP. Flutter no tiene mecanismo de backpressure en `socket.add()` — se acumulan en el buffer del kernel del SO hasta que WiFi los drena. Mientras tanto, nuevos frames se siguen encolando.
3.  **El hilo de encoding no tiene delay adaptativo**: `encodingLoop` en Kotlin procesa frames a máxima velocidad sin medir el throughput de salida. Si la red es lenta, el buffer interno crece sin límite hasta que frames colapsan o se corrompen.
4.  **`mediaCodec.dequeueInputBuffer(10_000)` con timeout alto**: Si el codec está ocupado (por frames grandes), bloquea 10ms por intento, reduciendo el FPS efectivo.

### Soluciones Pendientes (Orden de Impacto)

#### A — Reducir el timeout de `dequeueInputBuffer` (trivial, alto impacto)
En `H264EncoderPlugin.kt`, cambiar:
```kotlin
val idx = codec.dequeueInputBuffer(10_000)  // actual: 10ms
// →
val idx = codec.dequeueInputBuffer(0)  // 0 = no bloquear, skip si ocupado
```
Esto evita que el hilo de encoding se paralice esperando al codec.

#### B — Bitrate adaptativo según movimiento (medio, alto impacto)
Usar `MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME` y `PARAMETER_KEY_VIDEO_BITRATE` para ajustar el bitrate dinámicamente:
```kotlin
val params = Bundle()
params.putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, newBitrate)
codec.setParameters(params)
```
Bajar el bitrate cuando la cola de output crece (detectable midiendo `outputQueue.size`).

#### C — Backpressure en socket TCP desde la PC (complejo, alto impacto)
Implementar un canal de control bidireccional (segundo socket o mensajes de control en el mismo protocolo). La PC envía un mensaje `THROTTLE` cuando el buffer de decodificación se llena, y el teléfono reduce el FPS objetivo del encoder.

#### D — Surface-based encoding (complejo, máximo impacto)
Reemplazar el pipeline actual de `copyYuvToBuffer → MediaCodec InputBuffer` por encoding basado en `Surface`:
```kotlin
val surface = mediaCodec.createInputSurface()
// usar ImageReader o SurfaceTexture conectado a CameraX
```
Esto elimina por completo la copia YUV en CPU/JNI — la GPU mueve los datos directamente al encoder por hardware. Es la arquitectura que usan apps profesionales (Google Meet, WhatsApp Video).

---

## Estructura de Archivos Clave

```
OpenCamera/
├── README.md
├── session_context.md              # Este archivo
├── build_server.ps1                # Script para compilar el servidor PC
├── pc_server/
│   ├── CMakeLists.txt
│   └── src/
│       ├── main.cpp
│       ├── tcp_server.hpp/cpp      # Servidor TCP Winsock2
│       ├── frame_receiver.hpp/cpp  # Parseador (H264/JPEG/Text)
│       ├── jpeg_viewer.hpp/cpp     # Visor GDI+ con double-buffering
│       ├── h264_decoder.hpp/cpp    # Decodificador FFmpeg
│       └── config.hpp              # MAX_FRAME_SIZE, puerto, magic
├── mobile_app/
│   ├── lib/
│   │   ├── main.dart               # UI + socket + toggle H.264/JPEG
│   │   └── services/
│   │       ├── camera_service.dart # Rate limiting fire-and-forget YUV
│   │       └── h264_encoder.dart   # Polling de chunks via MethodChannel
│   └── android/.../kotlin/
│       ├── MainActivity.kt
│       └── H264EncoderPlugin.kt    # MediaCodec HW + NV21 copy + stride alineado
```

---

## Fase 4 — Cámara Virtual DirectShow (Plan Detallado)

### Objetivo
Crear un filtro DirectShow (`.ax` / `.dll`) que registre un dispositivo de captura virtual en Windows. Cualquier aplicación que use DirectShow o Media Foundation (OBS, Zoom, Teams, Skype, Discord) verá el dispositivo como "Cámara Libre" y podrá capturar el video del teléfono.

### Arquitectura

```
[camera_libre_server.exe]
        │  frames BGR24 decodificados (FFmpeg)
        ▼
[Shared Memory / Named Pipe]
        │
        ▼
[CameraLibreVCam.ax]  ← Filtro DirectShow (DLL COM)
  IBaseFilter + IKsPropertySet
  IPin (output) → entrega frames a aplicaciones
        │
        ▼
[OBS / Zoom / Teams / etc.]
```

### Componentes a Implementar

#### 1. `vcam_filter/` — Proyecto C++ (Visual Studio)
Crear un filtro DirectShow que implemente:
- `IBaseFilter` — filtro base DirectShow
- `IKsPropertySet` — propiedades de cámara (necesario para que Windows lo reconozca como cámara)
- `IAMStreamConfig` — configuración de formato de video (resolución, FPS)
- `CSourceStream` — stream de salida con `FillBuffer()` que lee frames del servidor

Frameworks de referencia:
- **OBS VirtualCam** (código abierto, referencia directa): https://github.com/obsproject/obs-virtual-cam
- **UniversalVirtualCam**: simplificado, más fácil de entender
- **DirectShow BaseClasses** (Microsoft Samples): incluidos en Windows SDK bajo `Samples\multimedia\directshow\baseclasses`

#### 2. Mecanismo de IPC entre `server.exe` y el filtro
Opción recomendada: **Named Shared Memory** (`CreateFileMapping` + `MapViewOfFile`)
- El servidor escribe el último frame BGR24 en memoria compartida: `"CameraLibre_Frame"`
- El filtro DirectShow lo lee en `FillBuffer()` a la tasa de FPS configurada
- Ventaja: zero-copy, latencia < 1ms, sin serialización

Alternativa: **Named Pipe** (más fácil de implementar pero más lento)

#### 3. Registro del filtro COM
```powershell
# Registrar el filtro (requiere admin):
regsvr32 CameraLibreVCam.ax

# Verificar que aparece como dispositivo:
# Abrir OBS → Fuentes → Dispositivo de captura de video → buscar "Cámara Libre"
```

#### 4. Instalador
- Script `.bat` o `.ps1` que:
  1. Copia `CameraLibreVCam.ax` a `C:\Program Files\CameraLibre\`
  2. Ejecuta `regsvr32` como admin
  3. Registra el servidor como servicio de Windows (opcional)

### Herramientas Necesarias para Fase 4
| Herramienta | Propósito | Cómo obtener |
|---|---|---
| Visual Studio 2022 | Compilar el filtro COM (`.ax`) | https://visualstudio.microsoft.com |
| Windows SDK 10+ | Headers DirectShow, COM | Incluido en Visual Studio |
| DirectShow BaseClasses | `CSource`, `CSourceStream`, etc. | Windows SDK Samples, compilar como `.lib` |
| `regsvr32` | Registrar el filtro COM | Incluido en Windows |

### Orden de Implementación Sugerido
1. Crear el filtro DirectShow mínimo (sin datos reales, solo frame negro) y verificar que OBS lo detecta.
2. Implementar la shared memory en `camera_libre_server.exe` — escribir el último frame BGR24 cada vez que FFmpeg lo decodifica.
3. Conectar el filtro a la shared memory — leer el frame en `FillBuffer()`.
4. Probar en OBS, Zoom, Teams.
5. Crear el instalador.

---

## Entorno de Desarrollo

- **OS**: Windows 10/11
- **Flutter/Dart**: 3.41.9 / 3.11.5
- **C++ Compiler**: GCC 15.2.0 (MSYS2/MinGW64)
- **CMake**: 4.2.3
- **FFmpeg (PC)**: MinGW64 (`libavcodec`, `libavformat`, `libavutil`, `libswscale`)
- **Shell**: PowerShell

---

## Protocolo de Comunicación H.264

### Móvil → PC
```
[Cámara YUV] → [camera_service.dart: fire-and-forget] → [H264EncoderPlugin.kt]
→ [copyYuvToBuffer: NV21 alineado a stride=736] → [MediaCodec HW encoder]
→ [NAL Units Annex B + SPS/PPS en keyframes] → [Socket TCP]
```

### PC → Pantalla
```
[Socket TCP] → [FrameReceiver: isH264()] → [H264Decoder: avcodec_send_packet]
→ [avcodec_receive_frame] → [sws_scale: YUV→BGR24] → [JpegViewer: GDI+ double-buffer]
```

---

## QUÉ DEBE HACER LA SIGUIENTE IA

### Estado Actual
- **H.264**: Funcional ✅. Colores correctos ✅. 18-20 FPS en escenas estáticas ✅. FPS bajo (5) con movimiento ⚠️. Latencia perceptible ⚠️.
- **JPEG**: Totalmente funcional como fallback ✅.
- **PC Server**: Estable, sin crashes ni fugas de memoria ✅.

### Prioridad 1 — Resolver FPS bajo con movimiento
Implementar las soluciones A y B descritas arriba en orden:
1. Cambiar `dequeueInputBuffer(10_000)` → `dequeueInputBuffer(0)` en `H264EncoderPlugin.kt`
2. Implementar bitrate adaptativo con `PARAMETER_KEY_VIDEO_BITRATE`
3. (Avanzado) Migrar a Surface-based encoding con CameraX

### Prioridad 2 — Fase 4: Cámara Virtual DirectShow
Seguir el plan detallado de la sección anterior. Punto de partida recomendado: estudiar el código fuente de **OBS VirtualCam** como referencia de implementación de `CSourceStream`.
