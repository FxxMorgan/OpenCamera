# Camera Libre -- OpenCamera

<div align="center">

[![Build-Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg?style=for-the-badge&logo=github)](https://github.com/FxxMorgan/OpenCamera)
[![Language-C++17](https://img.shields.io/badge/C%2B%2B-17-blue.svg?style=for-the-badge&logo=c%2B%2B)](https://en.cppreference.com/)
[![Framework-Flutter](https://img.shields.io/badge/Flutter-3.x-02569B.svg?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![Platform-Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4.svg?style=for-the-badge&logo=windows)](https://microsoft.com)
[![DirectShow](https://img.shields.io/badge/API-DirectShow-FF5722.svg?style=for-the-badge&logo=microsoft)](https://learn.microsoft.com/en-us/windows/win32/directshow/directshow)
[![License-GPL3](https://img.shields.io/badge/License-GPL%20v3-blue.svg?style=for-the-badge)](https://www.gnu.org/licenses/gpl-3.0)

**Alternativa open-source de alto rendimiento a DroidCam. Convierte tu smartphone Android en una webcam HD virtual de latencia ultra-baja en tu PC con Windows 10/11. Sin marcas de agua. Codigo fuente abierto.**

</div>

---

## Que es Camera Libre

Muchas aplicaciones que convierten el telefono en webcam estan plagadas de publicidad, marcas de agua, limites de tiempo o suscripciones mensuales.

Camera Libre nace como una solucion tecnica de codigo abierto que prioriza el rendimiento. Combina un cliente ligero en Flutter (Dart + Android Kotlin nativo) con un servidor y un filtro de sistema DirectShow (C++) para Windows. A traves de codificacion y decodificacion directa por hardware, logramos un stream fluido y estable de 1280x720 a 30 FPS con latencia de apenas unos pocos milisegundos, convirtiendo tu smartphone en un periferico nativo del sistema operativo.

### Modelo de distribucion

Camera Libre esta publicado bajo la licencia **GPL-3.0**. El codigo fuente completo esta disponible en GitHub y cualquier persona puede compilarlo, usarlo y modificarlo libremente.

La version distribuida a traves de Google Play Store incluye publicidad no intrusiva o un pago unico minimo como metodo de financiamiento del desarrollo continuo. Los usuarios que prefieran una experiencia completamente libre de anuncios pueden compilar la aplicacion directamente desde el repositorio sin ninguna restriccion.

---

## Caracteristicas

- **Latencia ultra-baja**: Codificacion de hardware por MediaCodec H.264 (AVC) en Android y decodificacion por hardware/software asincrona FFmpeg en la PC.
- **Conexion local directa**: Comunicacion directa via Sockets TCP sin pasar por servidores de terceros. Tus datos nunca salen de tu red.
- **Camara virtual DirectShow nativa (.ax)**: Registrada en el sistema COM para ser compatible con Discord Desktop, OBS Studio, Google Chrome, Microsoft Edge, Firefox, Zoom y Teams.
- **Colores corregidos de alta fidelidad**: Conversion de color BGR24 a YUY2 optimizada a nivel binario que elimina los tonos azulados y restituye los colores calidos naturales.
- **Preview nativa zero-copy**: La previsualizacion en el telefono utiliza una textura de hardware nativa de Flutter conectada directamente a la superficie de Camera2, sin copias intermedias de frames en memoria.
- **Compensacion de exposicion automatica**: El motor nativo aplica una compensacion AE de +4 EV sobre el template de grabacion para igualar el brillo de la app de camara nativa del dispositivo.
- **Orientacion de stream configurable**: Soporte para transmision en modo vertical (9:16) y horizontal (16:9) con previsualizacion adaptativa en el dispositivo.
- **Auto-dim inteligente**: Tras 5 segundos de streaming sin actividad tactil, la previsualizacion se atenua al 30% de opacidad para reducir el consumo de GPU y bateria.
- **Deteccion de IP local**: Monitor de IP local integrado en la aplicacion para facilitar la sincronizacion con el servidor PC.
- **IPC robusto de memoria compartida**: Sincronizacion basada en memoria mapeada con proteccion de lectura compartida. Si la aplicacion movil se desconecta, el filtro de la camara virtual permanece activo en Discord/OBS mostrando un buffer seguro sin congelar el software cliente.

---

## Arquitectura

El siguiente flujo ilustra el ciclo de vida de un frame de video, desde el sensor de la camara hasta las aplicaciones cliente de Windows:

```
[Sensor de Camara Android]
        |
        v
[H264EncoderPlugin - Kotlin]
   Camera2 API + MediaCodec AVC (Hardware)
   Compensacion AE +4 EV
   Superficie zero-copy compartida con preview
        |
        v
[Socket TCP Cliente - Kotlin nativo]
   Protocolo CLFR: [MAGIC 4B][SIZE 4B][PAYLOAD]
        |
        | Wi-Fi / Red Local TCP:8080
        v
[Socket TCP Server - C++]
   Parser de cabeceras CLFR
        |
        v
[H264Decoder - FFmpeg libavcodec]
   Decodificacion + Escala Bilineal 1280x720
        |
        v
[Memoria Compartida Global IPC]
   frame.dat - OPEN_ALWAYS
        |
        v
[Filtro DirectShow - CameraLibreVCam.ax]
   Conversion RGB24 -> YUY2 (Chromium)
   Fallback BGR24 (Firefox/Legacy)
        |
        v
[Discord / OBS / Chrome / Zoom / Teams]
```

---

## Roadmap

### Completado

| Fase | Descripcion | Estado |
|------|------------|--------|
| 1 | Transmision de red basica: Sockets TCP raw + empaquetador de tramas estructurado (framing) | Completado |
| 2 | Stream JPEG + Preview: Transmision por cuadros JPEG y visor nativo de preview GDI+ en Windows | Completado |
| 3 | Transmision H.264 de alto rendimiento: Codificador de hardware Android (MediaCodec) y decodificador libavcodec FFmpeg en PC | Completado |
| 4 | Filtro de camara virtual nativo: Desarrollo del filtro COM DirectShow .ax con soporte de formato indexado (YUY2 prioritario + RGB24) | Completado |
| 5 | UI movil premium y motor nativo: Interfaz de alto contraste, auto-dim para bateria, preview zero-copy por textura nativa, compensacion de exposicion AE, soporte de orientacion vertical/horizontal | Completado |

### En desarrollo

| Fase | Descripcion | Prioridad |
|------|------------|-----------|
| 6 | Instalador MSI para Windows: Empaquetador que registre el filtro DirectShow, instale el servidor y cree accesos directos sin intervencion manual | Alta |
| 7 | Interfaz grafica del servidor PC: Reemplazar la consola por una GUI nativa con previsualizacion del stream, indicadores de conexion y controles de configuracion | Alta |
| 8 | Bitrate dinamico adaptativo: Ajuste automatico del bitrate de codificacion H.264 en funcion de la calidad y latencia de la senal Wi-Fi en tiempo real | Media |

### Planificado

| Fase | Descripcion | Prioridad |
|------|------------|-----------|
| 9 | Publicacion en Google Play Store: Preparacion de la build de release firmada, listado en la tienda con monetizacion (anuncios o pago unico) | Alta |
| 10 | Transmision por cable USB (ADB): Canal de datos alternativo para entornos sin Wi-Fi o con redes restringidas | Media |
| 11 | Control de camara avanzado: Zoom tactil, enfoque manual, balance de blancos y seleccion de lente en dispositivos multi-camara | Baja |
| 12 | Soporte multi-plataforma PC: Evaluacion de compatibilidad con macOS (AVFoundation) y Linux (V4L2) | Baja |

---

## Estructura del proyecto

```
/mobile_app     Aplicacion movil Flutter. Pipeline de captura en Dart y
                encoder de hardware nativo en Kotlin (Camera2 + MediaCodec).

/pc_server      Servidor receptor TCP de consola en C++17. Decodifica el
                stream H.264 con FFmpeg y alimenta la memoria compartida.

/vcam_filter    Codigo fuente de la camara virtual DirectShow C++.
                Se compila como DLL de Windows con extension .ax.
```

---

## Inicio rapido

Consulta las guias detalladas para compilar y operar el sistema:

- [Guia de compilacion](BUILDING.md) -- Compilar el servidor, el filtro DirectShow y la app movil.
- [Guia de uso](USAGE.md) -- Registrar la camara virtual, iniciar el servidor e integrar con Discord/OBS.
- [Guia de contribucion](CONTRIBUTING.md) -- Directrices de codigo, proceso de pull requests y reporte de bugs.

---

## Contribuciones

Todas las contribuciones son bienvenidas. Si deseas proponer cambios, corregir bugs o implementar funciones nuevas, consulta la [Guia de Contribucion](CONTRIBUTING.md) y el [Codigo de Conducta](CODE_OF_CONDUCT.md).

---

## Licencia

Copyright (c) 2026 FxxMorgan / Feer / Camera Libre Contributors

Este proyecto se distribuye bajo la **GNU General Public License v3.0**. Consulta el archivo [LICENSE](LICENSE) para los terminos completos.

Como titular del copyright, el autor se reserva el derecho de distribuir versiones comerciales del software (por ejemplo, a traves de Google Play Store) bajo terminos adicionales. Esta capacidad no afecta los derechos de los usuarios bajo la GPL-3.0: cualquier persona puede obtener, compilar, modificar y redistribuir el codigo fuente conforme a los terminos de la licencia.
