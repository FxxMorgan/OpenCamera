# 🛠️ Guía de Compilación — BUILDING.md

Esta guía detalla paso a paso cómo compilar todos los componentes de **Cámara Libre (OpenCamera)**: el servidor de procesamiento en Windows, el filtro de cámara virtual DirectShow (en C++ nativo) y la aplicación móvil en Android (en Flutter).

Compilar código C++ en Windows puede ser complejo debido a la gestión de dependencias y compiladores. Para hacer este proceso lo más sencillo, rápido y libre de fricción posible, **este proyecto utiliza MSYS2 con la cadena de herramientas MinGW-w64**.

---

## 💻 1. Compilación del Host (Windows - C++)

### A. Requisitos Previos

Debes instalar **MSYS2**, un gestor de paquetes de software para Windows que nos proveerá el compilador `g++`, `cmake`, `make` y las librerías de desarrollo de **FFmpeg** nativas para 64 bits.

1. Descarga e instala **MSYS2** desde su sitio oficial: [msys2.org](https://www.msys2.org/).
2. Abre la terminal de **MSYS2 UCRT64** o **MSYS2 MINGW64** desde tu menú de inicio de Windows.
3. Ejecuta el siguiente comando para actualizar la base de datos de paquetes e instalar las herramientas necesarias:
   ```bash
   pacman -S --needed mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ffmpeg
   ```
   *Esto instalará:*
   *   **Compilador GCC/G++ 11+** (`mingw-w64-x86_64-toolchain`)
   *   **CMake** (`mingw-w64-x86_64-cmake`)
   *   **Librerías FFmpeg** (`libavcodec`, `libswscale`, `libavutil` compiladas nativamente para MinGW-64)

### B. Configuración de Variables de Entorno

Para que los scripts de PowerShell y CMake localicen el compilador de forma automática:
1. Copia la ruta de binarios de MinGW (por defecto es `C:\msys64\mingw64\bin`).
2. Abre el buscador de Windows, escribe **"variables de entorno"** y selecciona **Editar las variables de entorno del sistema**.
3. Haz clic en **Variables de entorno**.
4. En **Variables del sistema**, busca `Path` y haz clic en **Editar**.
5. Añade la ruta anterior (ej. `C:\msys64\mingw64\bin`) y pulsa **Aceptar**.

> [!TIP]
> **Nota de Ruta**: Si instalaste MSYS2 en una unidad diferente a la unidad `C:` (por ejemplo, en `A:\msys64`), abre los archivos [build_server.ps1](file:///d:/Programacion/OpenCamera/build_server.ps1) y [build_vcam.ps1](file:///d:/Programacion/OpenCamera/build_vcam.ps1) y edita la línea `$CMAKE = ...` para que coincida con tu ruta de instalación.

---

### C. Compilación del Filtro de Cámara Virtual (`.ax`)

El filtro DirectShow de Windows se compila como una DLL dinámica COM enlazada estáticamente a la librería de clases base de DirectShow (`BaseClasses/`) provista en el repositorio.

Abre **PowerShell** en la raíz del proyecto y ejecuta:
```powershell
# Compilar el filtro de cámara virtual
.\build_vcam.ps1
```

**¿Qué hace este script?**
* Ejecuta CMake con el generador `"MinGW Makefiles"`.
* Enlaza estáticamente la cabecera e implementaciones de DirectShow.
* Genera el filtro compilado con extensión `.ax` en: `vcam_filter/build/libCameraLibreVCam.ax`.

---

### D. Compilación del Servidor de Procesamiento PC (`.exe`)

El servidor recibe el flujo TCP H.264 del móvil, lo decodifica usando FFmpeg, lo redimensiona de forma estable a 1280x720 y alimenta la memoria compartida (IPC) del filtro DirectShow.

En tu terminal **PowerShell** en la raíz del proyecto, ejecuta:
```powershell
# Compilar el servidor de PC
.\build_server.ps1
```

**¿Qué hace este script?**
* Ejecuta CMake en la carpeta `pc_server/`.
* Vincula de forma nativa las librerías dinámicas de FFmpeg.
* Compila el ejecutable optimizado de lanzamiento (`Release`) en: `pc_server/bin/camera_libre_server.exe`.

---

## 📱 2. Compilación de la Aplicación Móvil (Android - Flutter)

La aplicación de Android captura el feed de la cámara local, utiliza el codificador por hardware nativo MediaCodec H.264 para reducir el uso de CPU a cero, y transmite los paquetes a través de un socket TCP cliente asíncrono.

### A. Requisitos Previos

1. **Flutter SDK**: Instala Flutter (versión 3.x recomendada). Asegúrate de que `flutter doctor` pase sin errores.
2. **Android SDK & Command Line Tools**: Configura el SDK de Android en tu sistema y asegúrate de tener una versión de Gradle/SDK compatible configurada por Flutter.
3. **Dispositivo Físico Android**: Habilita las **Opciones de desarrollador** y la **Depuración USB** en tu smartphone. *(No se recomienda usar emuladores debido a la falta de codificadores AVC por hardware y retrasos de red emulada).*

### B. Permisos Requeridos (Android)

La aplicación solicita los siguientes permisos en su archivo `AndroidManifest.xml` para poder operar:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```
*(WAKE_LOCK es gestionado a través de `wakelock_plus` para impedir que el teléfono apague la pantalla o la CPU suspenda el socket TCP durante la transmisión en vivo).*

### C. Comandos de Compilación y Lanzamiento

Conecta tu teléfono por USB al PC, abre la terminal en la carpeta `/mobile_app` y ejecuta:

```bash
# 1. Obtener dependencias de Flutter
flutter pub get

# 2. Compilar e instalar en modo de alto rendimiento (Release) en el dispositivo
flutter run --release
```

Si deseas generar el paquete instalable final (`.apk`) para compartirlo o guardarlo en tu teléfono de forma permanente:
```bash
# Generar un APK optimizado para arquitectura de 64 bits (arm64-v8a)
flutter build apk --release --target-platform android-arm64
```
El archivo `.apk` resultante se guardará en:  
`mobile_app/build/app/outputs/flutter-apk/app-release.apk`.

---

## 📋 Resumen de Archivos Compilados

Al completar la guía de compilación, tendrás los 3 artefactos esenciales listos para operar:
1. 📱 **Móvil**: `app-release.apk` (Instalado en tu teléfono).
2. 💻 **Servidor**: `pc_server/bin/camera_libre_server.exe` (Ejecutable de consola del host).
3. 🎥 **Filtro**: `vcam_filter/build/libCameraLibreVCam.ax` (DLL COM del sistema operativo Windows).
