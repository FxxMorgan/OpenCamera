# Plan: Fix Discord Grey Screen by Supporting YUY2 Color Format

## Context & Finding
* **Webcamtests.com** (Chrome) works perfectly! This validates that registration, IPC mapping, and basic DirectShow functions are healthy.
* **Discord Desktop** detects the camera name but shows a **constant loading grey/black screen** and fails to render.
* **Key Diagnostic**: We verified Discord (PID 12524) *did* load our `CameraLibreVCam.ax` DLL, but the stream constructor/destructor logs were never invoked by Discord.
* **Causa Raíz**: Discord uses Chromium's WebRTC engine for video capture. Chromium's WebRTC capture implementation prioritizes/requires YUV-based pixel formats (typically `YUY2`, `NV12`, or `I420`) to feed directly into hardware H.264/VP8 encoders. Because our filter currently **only** advertises and accepts `RGB24`, Discord rejects it during format negotiation before starting the stream.

---

## Proposed Changes

To fix this, we will add support for **YUY2 (YUV 4:2:2)** as our primary/preferred format, while maintaining **RGB24** as a fallback for maximum compatibility.

No modifications are needed for the PC server (`camera_libre_server.exe`) or the shared memory IPC! The server will continue writing fast, uncompressed `RGB24` to `frame.dat`. The DirectShow filter will handle the **RGB24 → YUY2 conversion in-memory on-the-fly** during `FillBuffer()`.

### DirectShow Filter Changes

#### [MODIFY] [CameraLibreStream.cpp](file:///d:/Programacion/OpenCamera/vcam_filter/src/CameraLibreStream.cpp)

1. **Advertise Multiple Formats**:
   * Update `GetNumberOfCapabilities` to return `2`.
   * Update `GetStreamCaps` to handle `iIndex == 0` (YUY2) and `iIndex == 1` (RGB24).
   * Update `GetMediaType` to construct:
     * Index `0`: `MEDIASUBTYPE_YUY2` (16 bits-per-pixel, `'YUY2'` compression, size `width * height * 2`).
     * Index `1`: `MEDIASUBTYPE_RGB24` (24 bits-per-pixel, standard RGB, size `width * height * 3`).

2. **Allow Format Checks**:
   * Update `CheckMediaType` to accept both `MEDIASUBTYPE_YUY2` and `MEDIASUBTYPE_RGB24`.

3. **On-The-Fly RGB24 → YUY2 Conversion**:
   * In `FillBuffer()`, query the active format using `m_mt.Subtype()`.
   * If the active format is `MEDIASUBTYPE_YUY2`:
     * Read the `RGB24` pixel data from `frame.dat` (which is written top-down by the server).
     * Since YUY2 is inherently a top-down format in DirectShow, we convert directly from the source RGB24 to the destination YUY2 without needing to flip vertically!
     * Use a highly optimized integer-based RGB-to-YUY2 conversion loop.
   * If the active format is `MEDIASUBTYPE_RGB24`:
     * Perform the standard bottom-up vertical flip copying that we already do.

---

## Technical Details: RGB24 to YUY2 Converter

In `CameraLibreStream.cpp`, we will define a fast conversion helper:

```cpp
static inline void ConvertRGB24ToYUY2(const uint8_t* rgb, uint8_t* yuy2, int width, int height) {
    int numPixels = width * height;
    for (int i = 0; i < numPixels; i += 2) {
        int rgbIdx1 = i * 3;
        int rgbIdx2 = (i + 1) * 3;

        uint8_t r1 = rgb[rgbIdx1];
        uint8_t g1 = rgb[rgbIdx1 + 1];
        uint8_t b1 = rgb[rgbIdx1 + 2];

        uint8_t r2 = rgb[rgbIdx2];
        uint8_t g2 = rgb[rgbIdx2 + 1];
        uint8_t b2 = rgb[rgbIdx2 + 2];

        // Standard ITU-R BT.601 YUV conversion using integer shifts for speed
        uint8_t y1 = static_cast<uint8_t>(((66 * r1 + 129 * g1 + 25 * b1 + 128) >> 8) + 16);
        uint8_t y2 = static_cast<uint8_t>(((66 * r2 + 129 * g2 + 25 * b2 + 128) >> 8) + 16);

        // Average colors for U and V (4:2:2 chroma subsampling)
        int rAvg = (r1 + r2) >> 1;
        int gAvg = (g1 + g2) >> 1;
        int bAvg = (b1 + b2) >> 1;

        uint8_t u = static_cast<uint8_t>(((-38 * rAvg - 74 * gAvg + 112 * bAvg + 128) >> 8) + 128);
        uint8_t v = static_cast<uint8_t>(((112 * rAvg - 94 * gAvg - 18 * bAvg + 128) >> 8) + 128);

        // YUY2 Byte layout: [Y0, U0, Y1, V0]
        int yuy2Idx = i * 2;
        yuy2[yuy2Idx]     = y1;
        yuy2[yuy2Idx + 1] = u;
        yuy2[yuy2Idx + 2] = y2;
        yuy2[yuy2Idx + 3] = v;
    }
}
```

---

## Verification Plan

### 1. Compile & Install
1. Stop the current stream.
2. Compile the new DLL using `build_vcam.ps1`.
3. Reinstall and re-register the DLL using the `force_reinstall.ps1` script (it handles stopping Windows Camera Frame Server and overwriting the locked DLL).

### 2. Verify on Web (Chrome)
1. Run `camera_libre_server.exe` and stream from the mobile app.
2. Open `https://es.webcamtests.com/` in Chrome.
3. Start the test. Verify it displays correctly.
4. Check `filter.log` to confirm Chrome selected `YUY2` (or falls back to `RGB24`).

### 3. Verify on Discord Desktop
1. Completely restart Discord (to clear any cached directshow monikers).
2. Go to **Settings > Voice & Video**.
3. Select **Cámara Libre Virtual Cam**.
4. Click **Test Video**. Verify it streams flawlessly!
5. Check `filter.log` to see Discord successfully negotiating and calling `FillBuffer`.
