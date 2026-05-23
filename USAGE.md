# Guia de Uso

Esta guia describe como operar, configurar y solucionar problemas de Camera Libre (OpenCamera) una vez que has completado la compilacion de sus componentes.

---

## Paso 1: Registrar el filtro de la camara virtual en Windows

Para que aplicaciones como Discord, OBS Studio o tu navegador web reconozcan la camara como un dispositivo de hardware fisico, el filtro COM de DirectShow (`.ax`) debe registrarse en el registro global de Windows.

### Registro automatizado (recomendado)

Abre una terminal de PowerShell con privilegios de Administrador en la raiz del proyecto y ejecuta:

```powershell
.\install_vcam.ps1
```

Que hace este script:
1. Crea de forma segura la carpeta de instalacion del sistema: `C:\Program Files\CameraLibre\`.
2. Si ya existia un filtro registrado, lo desregistra de forma silenciosa para evitar bloqueos del sistema.
3. Copia el archivo binario compilado `CameraLibreVCam.ax` a la carpeta del sistema.
4. Ejecuta la herramienta de registro de Windows: `regsvr32.exe /s "C:\Program Files\CameraLibre\CameraLibreVCam.ax"`.

### Registro manual (alternativa)

Si prefieres hacerlo de forma manual, abre una terminal de simbolo del sistema (CMD) como Administrador y ejecuta:

```cmd
:: 1. Crear el directorio de instalacion
mkdir "C:\Program Files\CameraLibre"

:: 2. Copiar el filtro compilado
copy "vcam_filter\build\libCameraLibreVCam.ax" "C:\Program Files\CameraLibre\CameraLibreVCam.ax"

:: 3. Registrar el filtro en Windows
regsvr32 "C:\Program Files\CameraLibre\CameraLibreVCam.ax"
```

Si el registro es exitoso, Windows mostrara un cuadro de dialogo confirmando: "DllRegisterServer en CameraLibreVCam.ax tuvo exito".

---

## Paso 2: Iniciar el servidor de procesamiento de PC

El servidor es el puente que recibe la senal de video y la escribe en el buffer compartido IPC.

1. Abre una terminal de consola en Windows (PowerShell o CMD).
2. Ejecuta el servidor desde su ruta binaria:
   ```powershell
   .\pc_server\bin\camera_libre_server.exe
   ```
3. La consola mostrara los detalles de la red local:
   ```text
   === Camera Libre -- Servidor H.264 ===
   [INFO] Winsock inicializado correctamente.
   [INFO] Escuchando conexiones TCP en puerto 8080...
   [INFO] Direcciones IP locales para conectar en el movil:
      -> 192.168.1.105
      -> 192.168.56.1
   ```
   Toma nota de la direccion IP de tu red local (generalmente la que inicia con `192.168.1.x` o `192.168.0.x`).

---

## Paso 3: Conectar la aplicacion de Android

1. Abre la aplicacion Camera Libre en tu smartphone Android.
2. Asegurate de que el telefono este conectado a la misma red Wi-Fi que tu PC.
3. En la pantalla principal, pulsa el icono de configuracion en la barra superior o el boton circular en la barra inferior. Esto desplegara el panel de configuracion deslizable.
4. Rellena los campos:
   - **IP del Servidor**: La IP que mostro tu consola de PC (ej. `192.168.1.105`).
   - **Puerto**: `8080` (por defecto).
5. Selecciona la orientacion del stream:
   - **Vertical**: Stream en formato 9:16. Ideal para uso general.
   - **Horizontal**: Stream en formato 16:9. Ideal para videoconferencias y streaming.
6. Selecciona la calidad del stream:
   - **Low**: 640p a 30 FPS. Menor consumo de ancho de banda.
   - **Medium**: 960p a 30 FPS. Balance entre calidad y rendimiento.
   - **High**: 1280p a 30 FPS. Maxima calidad.
7. Asegurate de que el codec este en **H.264 Hardware** (activado por defecto).
8. Pulsa el boton **CONECTAR AHORA**.
9. Una vez establecida la conexion, veras el indicador de estado LIVE en rojo en la parte superior del telefono junto con el contador de FPS en tiempo real.
10. **Ahorro de bateria (Auto-Dim)**: Tras 5 segundos de streaming sin tocar la pantalla, la previsualizacion se atenuara automaticamente al 30% de opacidad. Pulsa la pantalla en cualquier momento para restablecer la vista al 100%.

---

## Paso 4: Configurar los clientes de video (OBS / Discord)

### Discord Desktop

1. Ve a **Ajustes de usuario** (icono de engranaje abajo a la izquierda).
2. Selecciona **Voz y video** en el panel lateral izquierdo.
3. Desplazate hacia abajo hasta la seccion **Ajustes de video**.
4. En el menu desplegable de **Camara**, selecciona **Camera Libre Virtual Cam**.
5. Haz clic en **Probar video**. Veras tu stream con colores correctos de inmediato.

### OBS Studio

1. En la caja de **Fuentes**, haz clic en el boton `+`.
2. Selecciona **Dispositivo de captura de video**.
3. Nombralo (ej. *Camera Libre*) y haz clic en **Aceptar**.
4. En la propiedad **Dispositivo**, selecciona **Camera Libre Virtual Cam** de la lista desplegable.
5. Deja las propiedades en "Predeterminados del dispositivo" y haz clic en **Aceptar**.

---

## Solucion de problemas

### 1. El Firewall de Windows bloquea la conexion

Si la aplicacion movil se queda en "Conectando..." y luego da error de conexion, es probable que el Firewall de Windows este bloqueando las conexiones entrantes al puerto 8080.

**Solucion**: Abre PowerShell como Administrador y ejecuta este comando para crear una regla de entrada en tu Firewall de Windows:

```powershell
New-NetFirewallRule -DisplayName "Camera Libre Server" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow
```

### 2. El filtro no aparece en la lista de camaras en una aplicacion

Si el dispositivo de camara virtual no se muestra en una aplicacion especifica (pero si en OBS o Edge):

**Causa**: La aplicacion que estas usando es de 32 bits (x86). El compilador de MSYS2/MinGW compila por defecto en formato nativo de 64 bits (x64), por lo que el filtro se registra solo para 64 bits.

**Solucion**: Asegurate de descargar e instalar la version de 64 bits de la aplicacion cliente (ej. la version x64 de Discord Desktop o Zoom).

### 3. Error IPC 1224 (Could not create IPC file)

Este error se produce cuando el servidor intenta abrir o truncar el archivo de memoria compartida `frame.dat` mientras aplicaciones clientes mantienen bloqueada la vista de lectura.

**Solucion**: Este problema esta resuelto en la version actual mediante la bandera de apertura segura `OPEN_ALWAYS`. Si llegas a notar bloqueos por fallos de red extremos:

1. Cierra la aplicacion de captura (OBS/Discord).
2. Abre PowerShell como Administrador y ejecuta el script auxiliar para forzar la liberacion del driver y reinstalarlo:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scratch\reinstall_vcam.ps1
   ```

### 4. El video va lento o con tirones

- Asegurate de que el toggle de Codec en el menu de ajustes del movil este en H.264. El codificador de hardware comprime las imagenes a nivel de silicio, lo que reduce la carga de la red local un 90% comparado con JPEG software.
- Verifica que tu router local no este saturado de descargas pesadas en la misma frecuencia de 2.4 GHz. De ser posible, conecta tu telefono a una red Wi-Fi de 5 GHz.

### 5. La imagen se ve oscura comparada con la camara nativa

El motor de captura utiliza el template `TEMPLATE_RECORD` de Camera2 que tiende a usar exposicion mas conservadora. La compensacion AE de +4 EV esta aplicada por defecto. Si necesitas ajustar el brillo, modifica el valor de `boost` en el archivo `H264StreamingEngine.kt` (linea del `coerceAtMost`).
