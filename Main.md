Documento de Planificación: Proyecto "Camara Libre" (Nombre en código)
1. Resumen Ejecutivo
Camara Libre es un sistema de software compuesto por una aplicación móvil (Android) y un cliente de escritorio (Windows 10). Su objetivo principal es transformar un smartphone en una cámara web de alta definición para PC a través de la red local (Wi-Fi) o conexión USB, sin anuncios, sin marcas de agua y con la menor latencia posible. El sistema emulará un dispositivo de video en Windows (Cámara Virtual) para ser compatible nativamente con aplicaciones como Discord, OBS, Zoom, entre otras.

2. Stack Tecnológico
📱 Lado Móvil (Android)
Framework: Flutter (Dart) - Permite una UI rápida y acceso a canales nativos si es necesario.

Captura de Video: Paquete camera o camera_android_camerax para acceso profundo al hardware de la cámara.

Codificación: H.264 (mediante ffmpeg_kit_flutter o invocación de MediaCodec nativo vía MethodChannels).

Red: Sockets TCP/UDP usando la librería estándar dart:io.

💻 Lado PC (Windows 10)
Lenguaje Base: C++ (Estándar C++17 o superior).

Red: Sockets nativos de Windows (Winsock2) para la recepción de paquetes.

Decodificación: FFmpeg (librerías libavcodec / libavformat) o alternativamente OpenCV si se prefieren procesar frames crudos al inicio.

Controlador (Virtual Cam): DirectShow (Windows SDK - BaseClasses) para compilar un archivo .ax (Filtro de origen / Source Filter) que Windows registre como cámara web.

Interfaz de Usuario (Opcional): ImGui (liviano, se lleva bien con C++) o Qt (más completo) para la ventana de configuración.

3. Requisitos Funcionales (RF)
RF01 - Captura de Video: La app móvil debe poder acceder a la cámara frontal y trasera del dispositivo.

RF02 - Configuración de Calidad: La app móvil debe permitir al usuario seleccionar la resolución (ej. 720p, 1080p) y los FPS (30, 60).

RF03 - Transmisión de Datos: La app móvil debe transmitir el flujo de video en tiempo real hacia una dirección IP y puerto específicos vía TCP o UDP.

RF04 - Recepción de Datos: El cliente de PC debe poder escuchar en un puerto específico y recibir el flujo de video entrante.

RF05 - Cámara Virtual: El cliente de PC debe inyectar el video recibido en un filtro DirectShow para que el sistema operativo lo reconozca como un dispositivo de entrada de video.

RF06 - Control de Conexión: Ambas aplicaciones deben tener un botón de "Conectar / Desconectar".

RF07 - Indicador de Estado: La app de PC debe mostrar el estado actual ("Esperando conexión...", "Conectado", "Error").

4. Requisitos No Funcionales (RNF)
RNF01 - Latencia: El retraso entre la captura en el teléfono y la visualización en la PC (vidrio a vidrio) debe ser inferior a 150 milisegundos en una red local estable.

RNF02 - Consumo de Recursos (PC): El proceso en C++ no debe superar el 5% de uso de CPU en un procesador multi-núcleo (ej. Xeon E5-2670 V3) ni exceder los 150 MB de memoria RAM.

RNF03 - Autonomía (Móvil): La app en Flutter debe mantener la pantalla encendida o permitir transmisión en segundo plano, optimizando la codificación por hardware para no drenar la batería rápidamente.

RNF04 - Compatibilidad OS: El cliente de escritorio debe ser 100% compatible con Windows 10 de 64 bits.

RNF05 - Experiencia de Usuario: El sistema debe carecer completamente de anuncios publicitarios, rastreadores o marcas de agua.

RNF06 - Estabilidad de Red: El sistema debe manejar caídas de paquetes (si se usa UDP) sin colgar o crashear la aplicación de PC.

5. Estructura y Arquitectura del Sistema
El sistema sigue una arquitectura de Cliente (Teléfono) - Servidor (PC) a nivel de datos.

[ Smartphone (Flutter) ]                             [ PC Windows (C++) ]
       |                                                    |
 1. UI: Selecciona Cámara                             1. Ejecuta Server Socket
 2. CameraX: Obtiene Frame de Video                   2. Escucha en el Puerto (ej. 8080)
 3. Encoder: Comprime a H.264                         3. Decodificador: Lee stream H.264
 4. Red: Envía paquetes por Socket TCP/UDP  ====>     4. Filtro DirectShow: Recibe Frame
                                                      5. OS: Expone "Camara Libre" a Discord/OBS

6. Hoja de Ruta (Roadmap)
Fase 1: Pruebas de Concepto (Semanas 1-2)
Objetivo: Transmitir un frame estático o texto de un lado a otro.

Móvil: Crear un proyecto "Hola Mundo" en Flutter que envíe texto o una imagen "dummy" por un socket TCP a una IP manual.

PC: Crear una consola en C++ usando Winsock2 que reciba el dato y lo imprima en terminal.

Fase 2: El Flujo de Video Crudo (Semanas 3-4)
Objetivo: Transmitir video sin optimizar.

Móvil: Implementar el paquete camera en Flutter. Extraer frames en JPEG y enviarlos continuamente por el socket.

PC: Recibir los frames JPEG, usar OpenCV para decodificarlos y mostrarlos en una ventana de Windows (cv::imshow). Nota: Aquí la latencia será visible, es normal.

Fase 3: Optimización y Codificación (Semanas 5-6)
Objetivo: Bajar la latencia a niveles utilizables usando H.264.

Móvil: Integrar codificación de video. Enviar el stream codificado en lugar de fotos sueltas.

PC: Implementar libavcodec (FFmpeg) en C++ para reemplazar OpenCV en la decodificación. Lograr reproducción fluida a 30/60 FPS.

Fase 4: La Cámara Virtual (El Gran Reto) (Semanas 7-8)
Objetivo: Eliminar la ventana de previsualización e inyectar al OS.

PC: Estudiar la documentación de Microsoft DirectShow. Clonar el ejemplo clásico vcam (Virtual Cam de Microsoft SDK) o usar proyectos open-source de referencia.

PC: Conectar el decodificador de FFmpeg a los buffers de salida del filtro DirectShow. Probar la cámara en Discord o Chrome.

Fase 5: UI, UX y Pulido Final (Semanas 9-10)
Objetivo: Hacer que sea fácil de usar para el día a día.

Móvil: Interfaz limpia en Flutter para cambiar resolución, ver IP local actual y controlar el flash.

PC: Crear un instalador para registrar el filtro .ax en Windows (regsvr32) de forma automática, sin que tengas que usar la línea de comandos cada vez.