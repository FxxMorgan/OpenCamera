# Guia de Contribucion

Gracias por tu interes en colaborar con Camera Libre (OpenCamera). Todo aporte es valioso, desde reportar un bug, proponer mejoras en la documentacion, hasta escribir optimizaciones en C++ o refactorizar la app de Flutter.

Para mantener una colaboracion organizada y de alto nivel tecnico, sigue estas pautas.

---

## 1. Como reportar un bug

Si encuentras un error o un comportamiento inesperado:

1. **Busca en los Issues activos**: Asegurate de que nadie haya reportado el mismo problema antes.
2. **Abre un Issue**: Si es un problema nuevo, abre un Issue usando nuestra plantilla de reporte de bugs.
3. **Proporciona detalles tecnicos**:
   - Modelo de tu telefono Android y version de sistema operativo.
   - Tu version de Windows (ej. Windows 11 Home 23H2 x64).
   - La herramienta cliente de video que usabas (OBS Studio x64, Discord Desktop x64, etc.).
   - **Logs**: Pega el log de la consola del PC Server o adjunta extractos de errores relevantes para ayudarnos a identificar la causa.

---

## 2. Como proponer una caracteristica o mejora

Si tienes una idea para una nueva funcion (ej. transmision por cable USB, control de enfoque automatico, zoom tactil, etc.):

1. Abre un Issue de tipo **Feature Request** para discutir la viabilidad tecnica antes de escribir el codigo.
2. Explica con claridad el valor de la funcion y como se deberia comportar desde la perspectiva del usuario final.

---

## 3. Directrices de desarrollo (Code Style)

Para mantener la legibilidad y consistencia del codigo, sigue las siguientes reglas segun el lenguaje:

### C++ (Filtro DirectShow y Servidor PC)

- **Compatibilidad**: El codigo debe compilar con GCC/MinGW-w64 (C++17) de forma nativa sin depender de suites pesadas de MSVC o librerias dinamicas no estandar.
- **Formateo**:
  - Usa indentacion de 4 espacios (evita las tabulaciones duras).
  - Nombres de variables en `camelCase` o `snake_case` siguiendo las convenciones del modulo que estas modificando.
  - Manten las clases y metodos enfocados; evita inyectar dependencias globales de red o de sistema dentro del filtro DirectShow de forma sincrona para no bloquear el hilo de renderizado del host.

### Kotlin (Motor nativo Android)

- **Formateo**: Sigue las convenciones estandar de Kotlin (ktlint).
- **Threading**: Todo acceso a Camera2 y MediaCodec debe ejecutarse en threads dedicados (`HandlerThread`). No bloquees el hilo principal de Flutter.
- **Recursos**: Libera siempre las superficies, codificadores y sesiones de captura en el metodo `stop()`.

### Dart y Flutter (Aplicacion Movil)

- **Formateo**: Ejecuta siempre `dart format .` en la carpeta `/mobile_app` antes de confirmar tus cambios.
- **Lints**: Asegurate de resolver todas las sugerencias de `flutter analyze` para garantizar la robustez del codigo.
- **Eficacia**: Minimiza el uso de `setState()` en procesos asincronos de alta velocidad (como en la cola de envio de frames H.264). Prefiere buffers en memoria y timers de rediseno periodicos de baja frecuencia (ej. 1 Hz) para proteger la bateria del movil.

---

## 4. Proceso de Pull Requests (PR)

1. **Haz un Fork** del repositorio a tu cuenta personal.
2. **Crea una rama descriptiva** para tus cambios:
   ```bash
   git checkout -b feature/mi-nueva-funcion
   # o para corregir un bug:
   git checkout -b fix/error-resolucion-obs
   ```
3. **Realiza tus cambios** y haz commits claros y descriptivos:
   ```bash
   git commit -m "Fix: corregir alineacion de stride YUY2 para anchos impares"
   ```
4. **Verifica tu codigo localmente**: Asegurate de que el servidor y la app compilen limpiamente.
5. **Abre el Pull Request (PR)** hacia la rama `main` de nuestro repositorio original.
6. **Espera la revision**: Analizaremos tus cambios, te daremos feedback tecnico respetuoso si es necesario y los integraremos.

> **Advertencia**: Por favor, nunca subas archivos compilados (`.exe`, `.dll`, `.ax`, `.apk`, carpetas `build/` o `.dart_tool/`) en tu Pull Request. Asegurate de que tu `.gitignore` local este operando correctamente.
