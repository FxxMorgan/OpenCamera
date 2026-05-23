# Guia de Compilacion

Esta guia detalla paso a paso como compilar todos los componentes de Camera Libre (OpenCamera): el servidor de procesamiento en Windows, el filtro de camara virtual DirectShow (C++ nativo) y la aplicacion movil en Android (Flutter).

Compilar codigo C++ en Windows puede ser complejo debido a la gestion de dependencias y compiladores. Para hacer este proceso lo mas sencillo posible, este proyecto utiliza MSYS2 con la cadena de herramientas MinGW-w64.

---

## 1. Compilacion del Host (Windows - C++)

### A. Requisitos previos

Debes instalar MSYS2, un gestor de paquetes de software para Windows que provee el compilador `g++`, `cmake`, `make` y las librerias de desarrollo de FFmpeg nativas para 64 bits.

1. Descarga e instala MSYS2 desde su sitio oficial: [msys2.org](https://www.msys2.org/).
2. Abre la terminal de **MSYS2 UCRT64** o **MSYS2 MINGW64** desde tu menu de inicio de Windows.
3. Ejecuta el siguiente comando para actualizar la base de datos de paquetes e instalar las herramientas necesarias:
   ```bash
   pacman -S --needed mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ffmpeg
   ```
   Esto instalara:
   - Compilador GCC/G++ 11+ (`mingw-w64-x86_64-toolchain`)
   - CMake (`mingw-w64-x86_64-cmake`)
   - Librerias FFmpeg: `libavcodec`, `libswscale`, `libavutil` compiladas nativamente para MinGW-64

### B. Configuracion de variables de entorno

Para que los scripts de PowerShell y CMake localicen el compilador de forma automatica:

1. Copia la ruta de binarios de MinGW (por defecto es `C:\msys64\mingw64\bin`).
2. Abre el buscador de Windows, escribe "variables de entorno" y selecciona **Editar las variables de entorno del sistema**.
3. Haz clic en **Variables de entorno**.
4. En **Variables del sistema**, busca `Path` y haz clic en **Editar**.
5. Agrega la ruta anterior (ej. `C:\msys64\mingw64\bin`) y pulsa **Aceptar**.

> **Nota de ruta**: Si instalaste MSYS2 en una unidad diferente a `C:` (por ejemplo `A:\msys64`), abre los archivos `build_server.ps1` y `build_vcam.ps1` y edita la linea `$CMAKE = ...` para que coincida con tu ruta de instalacion.

---

### C. Compilacion del filtro de camara virtual (.ax)

El filtro DirectShow de Windows se compila como una DLL dinamica COM enlazada estaticamente a la libreria de clases base de DirectShow (`BaseClasses/`) provista en el repositorio.

Abre PowerShell en la raiz del proyecto y ejecuta:

```powershell
.\build_vcam.ps1
```

Que hace este script:
- Ejecuta CMake con el generador "MinGW Makefiles".
- Enlaza estaticamente la cabecera e implementaciones de DirectShow.
- Genera el filtro compilado con extension `.ax` en: `vcam_filter/build/libCameraLibreVCam.ax`.

---

### D. Compilacion del servidor de procesamiento PC (.exe)

El servidor recibe el flujo TCP H.264 del movil, lo decodifica usando FFmpeg, lo redimensiona de forma estable a 1280x720 y alimenta la memoria compartida (IPC) del filtro DirectShow.

En tu terminal PowerShell en la raiz del proyecto, ejecuta:

```powershell
.\build_server.ps1
```

Que hace este script:
- Ejecuta CMake en la carpeta `pc_server/`.
- Vincula de forma nativa las librerias dinamicas de FFmpeg.
- Compila el ejecutable optimizado de lanzamiento (Release) en: `pc_server/bin/camera_libre_server.exe`.

---

## 2. Compilacion de la aplicacion movil (Android - Flutter)

La aplicacion de Android captura el feed de la camara local, utiliza el codificador por hardware nativo MediaCodec H.264 para reducir el uso de CPU a cero y transmite los paquetes a traves de un socket TCP cliente asincrono manejado en Kotlin nativo.

### A. Requisitos previos

1. **Flutter SDK**: Instala Flutter (version 3.x recomendada). Asegurate de que `flutter doctor` pase sin errores.
2. **Android SDK y Command Line Tools**: Configura el SDK de Android en tu sistema y asegurate de tener una version de Gradle/SDK compatible configurada por Flutter.
3. **Dispositivo fisico Android**: Habilita las **Opciones de desarrollador** y la **Depuracion USB** en tu smartphone. No se recomienda usar emuladores debido a la falta de codificadores AVC por hardware y retrasos de red emulada.

### B. Permisos requeridos (Android)

La aplicacion solicita los siguientes permisos en su archivo `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

`WAKE_LOCK` es gestionado a traves de `wakelock_plus` para impedir que el telefono apague la pantalla o la CPU suspenda el socket TCP durante la transmision en vivo.

### C. Comandos de compilacion y lanzamiento

Conecta tu telefono por USB al PC, abre la terminal en la carpeta `/mobile_app` y ejecuta:

```bash
# 1. Obtener dependencias de Flutter
flutter pub get

# 2. Compilar e instalar en modo debug para desarrollo
flutter run

# 3. Compilar e instalar en modo release (alto rendimiento)
flutter run --release
```

Si deseas generar el paquete instalable final (.apk) para compartirlo:

```bash
# Generar un APK optimizado para arquitectura de 64 bits (arm64-v8a)
flutter build apk --release --target-platform android-arm64
```

El archivo `.apk` resultante se guardara en:
`mobile_app/build/app/outputs/flutter-apk/app-release.apk`.

---

## Resumen de archivos compilados

Al completar la guia de compilacion, tendras los 3 artefactos esenciales listos para operar:

| Componente | Archivo | Ruta |
|-----------|---------|------|
| Movil | `app-release.apk` | Instalado en tu telefono |
| Servidor | `camera_libre_server.exe` | `pc_server/bin/` |
| Filtro | `libCameraLibreVCam.ax` | `vcam_filter/build/` |
