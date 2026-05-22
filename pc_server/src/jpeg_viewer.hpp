#pragma once

// MinGW: wtypes.h + propidl.h must precede gdiplus.h to define PROPID
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <wtypes.h>
#include <propidl.h>
#include <objidl.h>
#include <gdiplus.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

/**
 * JpegViewer — Phase 2
 * Renders incoming JPEG frames in a Win32/GDI+ window.
 * Thread-safe: pushFrame() can be called from any thread.
 *
 * Architecture:
 *   - windowThread_ owns the HWND and runs the Win32 message loop.
 *   - pushFrame() copies JPEG bytes into backBuffer_, then
 *     PostMessage(WM_USER_NEW_FRAME) triggers a repaint on the window thread.
 */
class JpegViewer {
public:
    static constexpr UINT WM_NEW_FRAME = WM_USER + 1;

    struct Stats {
        uint64_t framesRendered = 0;
        uint64_t bytesRendered  = 0;
        double   fps            = 0.0;
    };

    explicit JpegViewer(int width = 1280, int height = 720);
    ~JpegViewer();

    // Start the viewer window (non-blocking — window runs in windowThread_).
    // Returns false if already running or window creation failed.
    bool start(const std::string& title = "Cámara Libre — Preview");

    // Signal the window to close and join the thread.
    void stop();

    // Push a new JPEG frame (Phase 2)
    void pushFrame(const uint8_t* jpegData, size_t jpegSize);

    // Push a raw RGB (BGR24) frame (Phase 3)
    void pushRgbFrame(const uint8_t* rgbData, int width, int height);

    bool     isRunning() const { return running_; }
    Stats    stats()     const;

private:
    int    width_, height_;
    std::string title_;

    std::atomic<bool> running_{false};
    std::thread       windowThread_;

    // Synchronization for window creation
    std::mutex              initMutex_;
    std::condition_variable initCv_;
    bool                    initDone_{false};
    bool                    initOk_{false};

    // Double buffer: producer writes backBuffer_, window reads frontBuffer_
    mutable std::mutex       frameMutex_;
    std::vector<uint8_t>     frontBuffer_, backBuffer_;
    std::atomic<bool>        hasNewFrame_{false};
    bool                     isRgbFrame_{false};
    int                      rgbWidth_{0}, rgbHeight_{0};

    // Stats
    mutable std::mutex statsMutex_;
    Stats              stats_;
    LARGE_INTEGER      lastFrameTime_{};
    LARGE_INTEGER      perfFreq_{};

    HWND               hwnd_{nullptr};
    ULONG_PTR          gdiplusToken_{0};

    // Window class name (unique per process via this pointer)
    std::string wndClassName_;

    void   windowLoop();
    void   onPaint(HDC hdc);
    void   updateStats(size_t frameSize);

    static LRESULT CALLBACK wndProcStatic(HWND hwnd, UINT msg,
                                           WPARAM wp, LPARAM lp);
    LRESULT wndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
};
