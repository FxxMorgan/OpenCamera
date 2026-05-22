# 📖 Guía de Uso — USAGE.md

Esta guía describe cómo operar, configurar y solucionar problemas de **Cámara Libre (OpenCamera)** una vez que has completado la compilación de sus componentes.

---

## 🎥 Paso 1: Registrar el Filtro de la Cámara Virtual en Windows

Para que aplicaciones como Discord, OBS Studio o tu navegador web reconozcan la cámara como un dispositivo de hardware físico, el filtro COM de DirectShow (`.ax`) debe registrarse en el registro global de Windows.

### A. Registro Automatizado (Recomendado)
Abre una terminal de **PowerShell con privilegios de Administrador** en la raíz del proyecto y ejecuta:
```powershell
.\install_vcam.ps1
```

**¿Qué hace este script de instalación?**
1. Crea de forma segura la carpeta de instalación del sistema: `C:\Program Files\CameraLibre\`.
2. Si ya existía un filtro registrado, lo desregistra de forma silenciosa para evitar bloqueos del sistema.
3. Copia el archivo binario compilado `CameraLibreVCam.ax` a la carpeta del sistema.
4. Ejecuta la herramienta de registro de Windows: `regsvr32.exe /s "C:\Program Files\CameraLibre\CameraLibreVCam.ax"`.

---

### B. Registro Manual (Alternativa)
Si prefieres hacerlo de forma manual, abre una terminal de **símbolo del sistema (CMD) como Administrador** y ejecuta:
```cmd
:: 1. Crear el directorio de instalación
mkdir "C:\Program Files\CameraLibre"

:: 2. Copiar el filtro compilado
copy "vcam_filter\build\libCameraLibreVCam.ax" "C:\Program Files\CameraLibre\CameraLibreVCam.ax"

:: 3. Registrar el filtro en Windows
regsvr32 "C:\Program Files\CameraLibre\CameraLibreVCam.ax"
```
*Si el registro es exitoso, Windows mostrará un cuadro de diálogo flotante confirmando: "DllRegisterServer en CameraLibreVCam.ax tuvo éxito".*

---

## 💻 Paso 2: Iniciar el Servidor de Procesamiento de PC

El servidor es el puente que recibe la señal de video y la escribe en el búfer compartido IPC.

1. Abre una terminal de consola en Windows (PowerShell o CMD).
2. Ejecuta el servidor desde su ruta binaria:
   ```powershell
   .\pc_server\bin\camera_libre_server.exe
   ```
3. La consola se encenderá mostrando los detalles de la red local:
   ```text
   === Cámara Libre — Servidor H.264 ===
   [INFO] Winsock inicializado correctamente.
   [INFO] Escuchando conexiones TCP en puerto 8080...
   [INFO] Direcciones IP locales para conectar en el móvil:
      -> 192.168.1.105
      -> 192.168.56.1
   ```
   *Toma nota de la dirección IP de tu red local (generalmente la que inicia con `192.168.1.x` o `192.168.0.x`).*

---

## 📱 Paso 3: Conectar la Aplicación de Android

1. Abre la aplicación **Cámara Libre** en tu smartphone Android.
2. Asegúrate de que el teléfono esté conectado a la **misma red Wi-Fi** que tu PC.
3. En la pantalla principal, presiona el botón circular principal de la parte inferior o la tuerca ⚙️ de la esquina. Esto desplegará la **pantalla de Configuración**.
4. Rellena los campos:
   *   **IP del Servidor**: La IP que mostró tu consola de PC (ej. `192.168.1.105`).
   *   **Puerto**: `8080` (por defecto).
5. Pulsa el botón **CONECTAR AHORA**.
6. Una vez establecida la conexión, verás el badge verde de **Conectado** en la parte superior del teléfono.
7. Presiona el botón flotante verde con icono de **Videocámara** en el móvil para iniciar el streaming en vivo.
8. **🔋 Ahorro de Batería (Auto-Dim)**: Tras 5 segundos de streaming sin tocar la pantalla, la previsualización del teléfono se atenuará automáticamente al 30% de opacidad para apagar virtualmente la pantalla y mitigar calentamientos. Pulsa la pantalla en cualquier momento para restablecer la vista al 100%.

---

## 🌐 Paso 4: Configurar los Clientes de Video (OBS / Discord)

### A. Discord Desktop
1. Ve a **Ajustes de usuario** (icono de engranaje abajo a la izquierda).
2. Selecciona **Voz y video** en el panel lateral izquierdo.
3. Desplázate hacia abajo hasta la sección **Ajustes de video**.
4. En el menú desplegable de **Cámara**, selecciona **Cámara Libre Virtual Cam**.
5. Haz clic en **Probar video**. Verás tu stream con colores perfectos de inmediato.

### B. OBS Studio
1. En la caja de **Fuentes**, haz clic en el botón `+`.
2. Selecciona **Dispositivo de captura de video**.
3. Nómbralo (ej. *Cámara Libre*) y haz clic en **Aceptar**.
4. En la propiedad **Dispositivo**, selecciona **Cámara Libre Virtual Cam** de la lista desplegable.
5. Deja las propiedades en "Predeterminados del dispositivo" y haz clic en **Aceptar**.

---

## 🔧 Solución de Problemas Comunes (Troubleshooting)

### 1. 🛑 El Firewall de Windows bloquea la conexión
Si la aplicación móvil se queda en "Conectando..." y luego da error de conexión, es probable que el Firewall de Windows esté bloqueando las conexiones entrantes al puerto `8080`.
*   **Solución rápida**: Abre PowerShell como Administrador y ejecuta este comando para crear una regla de entrada definitiva en tu Firewall de Windows:
    ```powershell
    New-NetFirewallRule -DisplayName "Cámara Libre Server" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow
    ```

### 2. 🔲 El filtro no aparece en la lista de cámaras en una aplicación
Si el dispositivo de cámara virtual no se muestra en una aplicación específica (pero sí en OBS o Edge):
*   **Causa**: La aplicación que estás usando es de **32 bits (x86)**. El compilador de MSYS2/MinGW compila por defecto en formato nativo de **64 bits (x64)**, por lo que el filtro de la cámara virtual se registra para 64 bits. Las aplicaciones de 32 bits no pueden cargar DLLs de 64 bits en su espacio de direcciones.
*   **Solución**: Asegúrate de descargar e instalar la versión de 64 bits de la aplicación cliente (ej. la versión x64 de Discord Desktop o Zoom).

### 3. 💥 Error IPC 1224 (Could not create IPC file)
Este error se producía históricamente cuando el servidor intentaba abrir o truncar el archivo de memoria compartida `frame.dat` mientras aplicaciones clientes mantenían bloqueada la vista de lectura.
*   **Solución**: Hemos solucionado esto de raíz configurando el mapeador en modo de lectura-escritura concurrente mediante la bandera de apertura segura `OPEN_ALWAYS` en C++. Si llegas a notar bloqueos por fallos de red extremos:
    1. Cierra la aplicación de captura (OBS/Discord).
    2. Abre PowerShell como Administrador y ejecuta el script auxiliar para forzar la liberación del driver y reinstalarlo en milisegundos sin reiniciar la PC:
       ```powershell
       powershell -ExecutionPolicy Bypass -File .\scratch\reinstall_vcam.ps1
       ```

### 4. 📶 El video va lento o con tirones
*   **Solución**: Asegúrate de que el toggle de Codec en el menú de ajustes del móvil esté en **H.264**. El codificador de hardware comprime las imágenes a nivel de silicio, lo que reduce la carga de la red local un 90% comparado con JPEG software.
*   **Wi-Fi saturada**: Asegúrate de que tu router local no esté saturado de descargas o compresión pesada en la misma frecuencia de 2.4 GHz. De ser posible, conecta tu teléfono a una red Wi-Fi de 5 GHz.
