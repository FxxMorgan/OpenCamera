# 📸 Cámara Libre — OpenCamera

<div align="center">

[![Build-Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg?style=for-the-badge&logo=github)](https://github.com/FxxMorgan/OpenCamera)
[![Language-C++17](https://img.shields.io/badge/C%2B%2B-17-blue.svg?style=for-the-badge&logo=c%2B%2B)](https://en.cppreference.com/)
[![Framework-Flutter](https://img.shields.io/badge/Flutter-3.x-02569B.svg?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![Platform-Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4.svg?style=for-the-badge&logo=windows)](https://microsoft.com)
[![DirectShow](https://img.shields.io/badge/API-DirectShow-FF5722.svg?style=for-the-badge&logo=microsoft)](https://learn.microsoft.com/en-us/windows/win32/directshow/directshow)
[![License-MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

**Alternativa open-source de alto rendimiento a DroidCam, completamente gratuita y sin anuncios, que convierte tu smartphone Android en una webcam HD virtual de latencia ultra-baja en tu PC con Windows 10/11.**

</div>

---

## 📽️ Demostración Visual

Aquí puedes ver el sistema operando a pantalla completa en el teléfono Android (con atenuación inteligente de batería activa), transmitiendo en tiempo real mediante red local al servidor PC, decodificando y alimentando de forma transparente la cámara virtual en **OBS Studio** y **Discord** con colores naturales corregidos.

<div align="center">
  <img src="C:/Users/Feer/.gemini/antigravity-ide/brain/fd4bc39f-1d28-44fb-a60f-22b5a8cad581/media__1779478822498.png" width="45%" alt="Vista de la Aplicación Móvil Premium" />
  <img src="C:/Users/Feer/.gemini/antigravity-ide/brain/fd4bc39f-1d28-44fb-a60f-22b5a8cad581/media__1779479135327.png" width="45%" alt="Configuración de Cámara Virtual de Alta Estabilidad" />
  <p><i>Interfaz móvil Cyberpunk de alto contraste y panel de configuración de streaming DirectShow YUY2.</i></p>
</div>

*(Para agregar tu propio video o GIF de demostración en vivo, reemplaza estas imágenes en la carpeta del repositorio).*

---

## 💡 ¿Qué es Cámara Libre y por qué existe?

Muchas aplicaciones que convierten el teléfono en webcam están plagadas de publicidad molesta, marcas de agua intrusivas, límites de tiempo o suscripciones de pago mensuales.

**Cámara Libre** nace como una solución técnica y de código abierto sólida que Prioriza el Rendimiento. Combina un cliente ligero en **Flutter (Dart + Android Kotlin nativo)** con un servidor y un filtro de sistema **DirectShow (C++)** de Windows. A través de la codificación y decodificación directa por hardware, logramos un stream fluido y estable de **1280x720 a 30 FPS** con una latencia de apenas unos pocos milisegundos, convirtiendo tu smartphone en un periférico nativo del sistema operativo.

---

## 🎨 Características Clave (Features)

*   ⚡ **Latencia Ultra-Baja**: Codificación de hardware por MediaCodec H.264 (AVC) en Android y decodificación por hardware/software asíncrona FFmpeg en la PC.
*   📶 **Conexión Local Directa**: Comunicación directa vía Sockets TCP sin pasar por servidores de terceros.
*   🎥 **Cámara Virtual DirectShow Nativa (`.ax`)**: Registrada en el sistema COM para ser compatible con cualquier software moderno como **Discord Desktop, OBS Studio, Google Chrome, Microsoft Edge, Firefox, Zoom y Teams**.
*   🌈 **Colores Corregidos de Alta Fidelidad**: Conversión de color BGR24 a YUY2 optimizada a nivel binario que elimina los tonos azulados y restituye los colores cálidos naturales (tonos de piel, ropa naranja/roja).
*   🔋 **Auto-Dim Inteligente**: Si la app móvil no detecta actividad táctil por 5 segundos en streaming, disminuye la opacidad de la pantalla al 30% para reducir el renderizado gráfico de la GPU, previniendo el sobrecalentamiento y ahorrando batería.
*   🌐 **IP local y detección automática**: Monitor de IP local en la app para facilitar la sincronización.
*   💼 **IPC Robusto de Memoria Compartida**: Sincronización basada en memoria mapeada en disco con protección de lectura compartida. Si la aplicación móvil se desconecta, el filtro de la cámara virtual permanece activo en Discord/OBS mostrando un búfer seguro sin congelar o bloquear el software cliente.

---

## 🏗️ Arquitectura General

El siguiente flujo ilustra el ciclo de vida de un frame de video, desde que el sensor de la cámara en el teléfono captura la luz hasta que se renderiza en aplicaciones cliente de Windows (Discord/OBS):

```mermaid
graph TD
    %% Teléfono Android
    subgraph Android_Phone [Dispositivo Android - Flutter/Kotlin]
        A[Sensor de Cámara] -->|Frames YUV| B[H264EncoderPlugin Kotlin]
        B -->|MediaCodec AVC Encoder| C[Cola de Compresión Max 2 Frames]
        C -->|Frames H.264 Codificados| D[Socket TCP Client Dart]
    end

    %% Red Local
    D -->|Wi-Fi / Red Local TCP:8080| E[Socket TCP Server C++]

    %% PC Host (Windows)
    subgraph PC_Host [Servidor de PC - C++]
        E -->|Parser de Cabeceras CLFR| F[H264Decoder FFmpeg]
        F -->|Decodificación + Escala Bilineal 1280x720| G[Memoria Compartida Global IPC]
    end

    %% DirectShow & Clients
    subgraph Windows_DirectShow [DirectShow Pipeline]
        G -->|Acceso Mapeado OPEN_ALWAYS| H[Filtro DirectShow CameraLibreVCam.ax]
        H -->|Conversión RGB24 -> YUY2| I[Format YUY2 Chromium-Compatible]
        H -->|Fallback Direct BGR| J[Format RGB24 Firefox/Legacy]
    end

    I --> K[Discord / Chrome / OBS Studio / Zoom]
    J --> L[Firefox / Software Legacy]

    style Android_Phone fill:#1e1e2f,stroke:#00E5FF,stroke-width:2px,color:#fff
    style PC_Host fill:#111c24,stroke:#00E5FF,stroke-width:2px,color:#fff
    style Windows_DirectShow fill:#122119,stroke:#00E676,stroke-width:2px,color:#fff
    style E fill:#ff6d00,stroke:#fff,stroke-width:1px,color:#fff
```

---

## 📈 Roadmap y Estado del Proyecto

- [x] **Fase 1: Transmisión de Red Básica** — Sockets TCP raw + empaquetador de tramas estructurado (Framing).
- [x] **Fase 2: Stream JPEG + Preview** — Transmisión por cuadros JPEG y visor nativo de preview GDI+ en Windows.
- [x] **Fase 3: Transmisión H.264 de Alto Rendimiento** — Codificador de hardware Android (`MediaCodec`) y decodificador `libavcodec` de FFmpeg en PC.
- [x] **Fase 4: Filtro de Cámara Virtual Nativo** — Desarrollo del filtro COM DirectShow `.ax` con soporte de formato indexado (YUY2 prioritario + RGB24).
- [x] **Fase 5: UI Móvil Premium y GPU Layering** — Nueva interfaz Cyberpunk de alto contraste, protección contra notches de pantalla, auto-dim para batería, cola H.264 reducida a 2 frames y corrección de color YUV a RGB.
- [ ] **Fase 6: Próximos Pasos (En Desarrollo)** — Cliente de configuración visual nativo para Windows (GUI), soporte de bitrate dinámico según la calidad de la señal Wi-Fi, y empaquetador final con instalador `.msi`.

---

## 📦 Estructura de Carpetas

*   [`/mobile_app`](file:///d:/Programacion/OpenCamera/mobile_app): Aplicación móvil en Flutter. Contiene el pipeline de captura en Dart y el encoder de hardware nativo en Kotlin.
*   [`/pc_server`](file:///d:/Programacion/OpenCamera/pc_server): Servidor receptor TCP de consola en C++17 que decodifica el stream H.264 con FFmpeg y alimenta la memoria compartida.
*   [`/vcam_filter`](file:///d:/Programacion/OpenCamera/vcam_filter): Código fuente de la cámara virtual DirectShow C++. Se compila como una DLL de Windows con extensión `.ax`.
*   [`/scratch`](file:///d:/Programacion/OpenCamera/scratch): Utilidades, scripts de reinstalación y herramientas auxiliares de testeo.

---

## 🤝 Contribuciones

¡Todas las contribuciones son bienvenidas! Si deseas proponer cambios, corregir bugs o implementar funciones nuevas, lee nuestra [Guía de Contribución](file:///d:/Programacion/OpenCamera/CONTRIBUTING.md).

---

## 📜 Licencia

Este proyecto se distribuye bajo la Licencia **MIT**. Eres libre de usar, modificar y distribuir este software. Consulta el archivo [LICENSE](file:///d:/Programacion/OpenCamera/LICENSE) para más detalles.
