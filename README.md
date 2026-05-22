# 📸 Cámara Libre — OpenCamera

<div align="center">

[![Language-C++17](https://img.shields.io/badge/C%2B%2B-17-blue.svg?style=for-the-badge&logo=c%2B%2B)](https://en.cppreference.com/)
[![Framework-Flutter](https://img.shields.io/badge/Flutter-3.x-02569B.svg?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![Platform-Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4.svg?style=for-the-badge&logo=windows)](https://microsoft.com)
[![DirectShow](https://img.shields.io/badge/API-DirectShow-FF5722.svg?style=for-the-badge&logo=microsoft)](https://learn.microsoft.com/en-us/windows/win32/directshow/directshow)
[![License-MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

**Convierte tu smartphone Android en una webcam HD virtual de alto rendimiento para tu PC con Windows 10/11.**  
*Sin anuncios, sin marcas de agua, sin suscripciones, 100% de código abierto.*

</div>

---

## 🚀 Estado Actual: Fase 4 Completa ✅ | ¡Cámara Virtual 100% Operativa!

El sistema se encuentra en un estado maduro y estable. Se ha implementado e integrado de manera exitosa el **Filtro de Cámara Virtual DirectShow nativo**, lo que significa que el flujo de video de tu teléfono es capturado y expuesto en tu PC de forma nativa para **Discord, Microsoft Edge, Google Chrome, OBS Studio, Firefox, Zoom y Teams**.

```
  [ Teléfono Android (Flutter) ]
              │ (MediaCodec H.264 Encoder, NV21 con Stride de 32 bytes)
              ▼
          TCP / Wi-Fi
              ▼
     [ PC Server (C++) ]
              │ (FFmpeg decodifica H.264 + Redimensionado bilineal estático a 1280x720)
              ▼
   Búfer IPC de Memoria Compartida (C:\ProgramData\CameraLibre\frame.dat)
              │ (Acceso concurrente ultra seguro y robusto con OPEN_ALWAYS)
              ▼
   [ DirectShow Virtual Camera Filter COM (.ax) ]
              │
              ├── [ MEDIASUBTYPE_YUY2 ] (Prioritario) ──▶ Discord, Chrome, Edge (WebRTC)
              │     └─ Conversor BGR24 ➔ YUY2 optimizado a nivel de bit con mapeo de color correcto
              │
              └── [ MEDIASUBTYPE_RGB24 ] (Fallback) ──▶ Firefox y aplicaciones legacy
```

---

## 🎨 Características Clave

* **Resolución Estática Garantizada (1280x720 @ 30 FPS)**: Evita cortes, pérdidas de frames o loops infinitos de carga (spinning dots). La cámara virtual mantiene una negociación fija independientemente de las fluctuaciones de red.
* **Compatibilidad Absoluta (YUY2 + RGB24)**:
  * **YUY2 (prioritario)**: Soporta la exigente especificación de Chromium y WebRTC (Discord Desktop, Chrome, Edge), exigiendo anchos pares, orientación *top-down* (altura positiva `+720`), buffers exactos y conversión optimizada por software.
  * **RGB24 (fallback)**: Soporte heredado compatible con navegadores de motor independiente (como Firefox).
* **Corrección de Tono de Piel y Colores Reales**: Integración exacta de los canales de color en la conversión YUV, eliminando por completo la coloración azulada en la piel y devolviendo tonos naturales y precisos a las prendas u objetos (rojo/naranja real).
* **IPC Robusto Anticolisiones**: Mecanismo de sincronización basado en memoria mapeada en disco con protección de lectura abierta (`OPEN_ALWAYS`), permitiendo reiniciar el servidor en vivo sin causar caídas en las aplicaciones clientes activas que usan la cámara.
* **Compilación Nativa de Extrema Ligereza**: El filtro virtual `.ax` está enlazado estáticamente a la biblioteca de clases base de DirectShow (`strmbase`) y no requiere dependencias en tiempo de ejecución ni DLLs extras de MinGW.

---

## 📂 Estructura del Proyecto

```
OpenCamera/
├── mobile_app/           # Aplicación móvil Flutter (Android)
│   ├── lib/
│   │   ├── main.dart                  # UI de conexión, monitor de red y toggle H.264/JPEG
│   │   └── services/
│   │       ├── camera_service.dart    # Captura nativa + despacho fire-and-forget de buffers
│   │       └── h264_encoder.dart      # Wrapper Dart para MediaCodec
│   └── android/app/src/main/kotlin/...
│       └── H264EncoderPlugin.kt       # Encoder de hardware (MediaCodec AVC), alineación 32 bytes
│
├── pc_server/            # Servidor de procesamiento de PC (C++)
│   ├── src/
│   │   ├── main.cpp          # Punto de entrada de la consola y preview nativa
│   │   ├── tcp_server.cpp    # Socket Winsock2 receptor
│   │   ├── frame_receiver.cpp# Parser y clasificador de tramas
│   │   ├── h264_decoder.cpp  # Decodificador FFmpeg (libavcodec) + escalado bilineal estable
│   │   └── config.hpp        # Parámetros globales (Puertos, Magic Header "CLFR")
│   └── CMakeLists.txt
│
├── vcam_filter/          # Filtro de Cámara Virtual DirectShow (C++)
│   ├── src/
│   │   ├── CameraLibreFilter.cpp # Registro COM, declaración de pines y setup DirectShow
│   │   ├── CameraLibreStream.cpp # Consumo IPC y conversor BGR24 ➔ YUY2 / RGB24
│   │   └── DllSetup.cpp          # Configuración del DLL de registro de Windows
│   ├── BaseClasses/              # Clases base de DirectShow compiladas estáticamente
│   └── CMakeLists.txt
│
├── scratch/              # Scripts auxiliares y herramientas de desarrollo rápido
│   └── reinstall_vcam.ps1 # Instalador con elevación de Administrador para bypass de bloqueos
├── build_server.ps1      # Compilador rápido del servidor de PC
├── build_vcam.ps1        # Compilador rápido del filtro de cámara virtual
└── install_vcam.ps1      # Registrador general de la cámara en el sistema
```

---

## 🛠️ Requisitos de Compilación y Configuración

| Herramienta | Versión Recomendada | Propósito |
|---|---|---|
| **Flutter SDK** | `3.x` / Dart `3.x` | Compilar la app móvil (`mobile_app`) |
| **CMake** | `3.20+` | Generador de scripts de compilación para PC |
| **MinGW-w64 (GCC)**| `11.0+` (MSYS2) | Compilación nativa C++ en Windows |
| **FFmpeg Dev Libraries**| Incluido en MSYS2 (`libavcodec`, `libswscale`) | Decodificación y renderizado de frames en el servidor |

---

## 💻 Instrucciones de Uso

### Paso 1: Compilar e Instalar la Cámara Virtual
Abre una terminal PowerShell y compila el filtro COM (`CameraLibreVCam.ax`):
```powershell
# 1. Compila el filtro COM
.\build_vcam.ps1
```

A continuación, instala y registra el filtro en el sistema operativo. **Esto requiere privilegios de Administrador** debido a que escribe en `%ProgramFiles%` y registra componentes COM a nivel global en el registro de Windows:
```powershell
# 2. Registra el filtro COM en el sistema (ejecutar en terminal como Administrador)
.\install_vcam.ps1
```
*Nota: Si necesitas actualizar el filtro en el futuro mientras Discord u otra app está abierta, usa `powershell -ExecutionPolicy Bypass -File .\scratch\reinstall_vcam.ps1` como Administrador. Este script automáticamente detiene el Frame Server de Windows y renombra el binario bloqueado para actualizarlo sin necesidad de reiniciar tu PC.*

### Paso 2: Iniciar el Servidor de Procesamiento en PC
Compila el servidor y ejecútalo para que empiece a escuchar en el puerto `8080`:
```powershell
# 1. Compilar el servidor
.\build_server.ps1

# 2. Ejecutar el servidor
.\pc_server\bin\camera_libre_server.exe
```

### Paso 3: Instalar y Vincular la App Android
Conecta tu dispositivo Android por USB con Depuración activa y ejecuta:
```powershell
cd mobile_app
flutter run --release
```
1. Concede permisos de cámara en la app.
2. Asegúrate de que el toggle esté en **H.264** (máximo rendimiento).
3. Introduce la dirección IP local de tu PC (el servidor te la mostrará en consola, ej. `192.168.0.105`).
4. Pulsa **Conectar** y luego **Iniciar Streaming**.

### Paso 4: ¡A Disfrutar!
Abre **Discord**, **OBS Studio**, **Google Chrome** o **Microsoft Edge**, ingresa a la configuración de cámara y selecciona **Cámara Libre Virtual Cam**. Tu transmisión se encenderá de inmediato con colores hermosos, naturales y una tasa de refresco ultra fluida.

---

## 📈 Roadmap y Progreso

- [x] **Fase 1** — Sockets TCP raw + empaquetador de tramas (Framing).
- [x] **Fase 2** — Transmisión de video basada en imágenes JPEG + Visor nativo GDI+ en Windows.
- [x] **Fase 3** — Implementación de H.264 en Hardware (MediaCodec en Android) y decodificación por software en PC con FFmpeg.
- [x] **Fase 4** — Filtro de Cámara Virtual COM DirectShow (`CameraLibreVCam.ax`) con soporte de prioridad de formato YUY2, fallback RGB24 y lógica anticolisiones IPC.
- [ ] **Fase 5** — Interfaz de usuario mejorada en el Servidor PC, Bitrate Dinámico Adaptativo y empaquetado del Instalador final (`.msi`).

---

## 📜 Licencia

Este proyecto está bajo la Licencia **MIT**. Consulta el archivo `LICENSE` para más información.
