# 🤝 Guía de Contribución — CONTRIBUTING.md

¡Gracias por tu interés en colaborar con **Cámara Libre (OpenCamera)**! Todo aporte es valioso, desde reportar un bug, proponer mejoras en la documentación, hasta escribir optimizaciones en C++ o refactorizar la app de Flutter.

Para mantener una colaboración sana, organizada y de alto nivel técnico, te pedimos que sigas estas pautas.

---

## 🐛 1. ¿Cómo Reportar un Bug?

Si encuentras un error o un comportamiento inesperado:
1.  **Busca en los Issues activos**: Asegúrate de que nadie haya reportado el mismo problema antes.
2.  **Abre un Issue**: Si es un problema nuevo, abre un Issue usando nuestra plantilla de reporte de bugs.
3.  **Proporciona Detalles Técnicos**:
    *   Modelo de tu teléfono Android y versión de sistema operativo.
    *   Tu versión de Windows (ej. Windows 11 Home 23H2 x64).
    *   La herramienta cliente de video que usabas (OBS Studio x64, Discord Desktop x64, etc.).
    *   **Logs**: Pega el log de la consola del PC Server o adjunta extractos de errores relevantes para ayudarnos a identificar la causa.

---

## 💡 2. ¿Cómo Proponer una Característica o Mejora?

Si tienes una gran idea para una nueva función (ej. transmisión por cable USB, control de enfoque automático, zoom táctil, etc.):
1.  Abre un Issue de tipo **Feature Request** para discutir la viabilidad técnica antes de escribir el código.
2.  Explica con claridad el valor de la función y cómo se debería comportar desde la perspectiva del usuario final.

---

## 🛠️ 3. Directrices de Desarrollo (Code Style)

Para mantener la legibilidad y consistencia del código, sigue las siguientes reglas estilísticas según el lenguaje:

### A. C++ (Filtro DirectShow y Servidor PC)
*   **Compatibilidad**: El código debe compilar con **GCC/MinGW-w64 (C++17)** de forma nativa sin depender de suites pesadas de MSVC o librerías dinámicas no estándar.
*   **Formateo**:
    *   Usa indentación de 4 espacios (evita las tabulaciones duras).
    *   Nombres de variables en `camelCase` o `snake_case` siguiendo las convenciones del módulo que estás modificando.
    *   Mantén las clases y métodos enfocados; evita inyectar dependencias globales de red o de sistema dentro del filtro DirectShow de forma síncrona para no bloquear el hilo de renderizado del host.

### B. Dart y Flutter (Aplicación Móvil)
*   **Formateo**: Ejecuta siempre `dart format .` en la carpeta `/mobile_app` antes de confirmar tus cambios.
*   **Lints**: Asegúrate de resolver todas las sugerencias de `flutter analyze` para garantizar la robustez del código.
*   **Eficacia**: Minimiza el uso de `setState()` en procesos asíncronos de alta velocidad (como en la cola de envío de frames H.264). Prefiere buffers en memoria y timers de rediseño periódicos de baja frecuencia (ej. 1 Hz) para proteger la batería del móvil.

---

## 🚀 4. Proceso de Pull Requests (PR)

1.  **Haz un Fork** del repositorio a tu cuenta personal.
2.  **Crea una rama descriptiva** para tus cambios:
    ```bash
    git checkout -b feature/mi-nueva-funcion
    # o para corregir un bug:
    git checkout -b fix/error-resolucion-obs
    ```
3.  **Realiza tus cambios** y haz commits claros y descriptivos:
    ```bash
    git commit -m "Fix: corregir alineación de stride YUY2 para anchos impares"
    ```
4.  **Verifica tu código localmente**: Asegúrate de que el servidor y la app compilen limpiamente.
5.  **Abre el Pull Request (PR)** hacia la rama `main` de nuestro repositorio original.
6.  **Espera la revisión**: Analizaremos tus cambios, te daremos feedback técnico respetuoso si es necesario y los integraremos con mucho gusto.

> [!WARNING]
> **Archivos Binarios**: Por favor, **NUNCA** subas archivos compilados (`.exe`, `.dll`, `.ax`, `.apk`, carpetas `build/` o `.dart_tool/`) en tu Pull Request. Asegúrate de que tu `.gitignore` local esté operando correctamente.
