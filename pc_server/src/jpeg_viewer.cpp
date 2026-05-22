/**
 * jpeg_viewer.cpp — Phase 2
 * GDI+ Win32 window that decodes and renders incoming JPEG frames.
 * GDI+ is built into Windows — no external dependencies needed.
 *
 * MinGW note: propidl.h must come before gdiplus.h to provide PROPID.
 */

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
// Must be before gdiplus.h on MinGW — provides PROPID via wtypes.h
#include <windows.h>
#include <wtypes.h>
#include <propidl.h>
#include <objidl.h>   // IStream, CreateStreamOnHGlobal
#include <gdiplus.h>

#include <cstring>
#include <iostream>
#include <sstream>
#include <iomanip>
#include <algorithm>

#include "jpeg_viewer.hpp"

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "ole32.lib")

// ---------------------------------------------------------------------------
//  Constructor / Destructor
// ---------------------------------------------------------------------------

JpegViewer::JpegViewer(int width, int height)
    : width_(width), height_(height) {
    QueryPerformanceFrequency(&perfFreq_);
    QueryPerformanceCounter(&lastFrameTime_);
    // Use 'this' address to create a unique window class name
    std::ostringstream oss;
    oss << "CameraLibreViewer_" << reinterpret_cast<uintptr_t>(this);
    wndClassName_ = oss.str();
}

JpegViewer::~JpegViewer() {
    stop();
}

// ---------------------------------------------------------------------------
//  Public API
// ---------------------------------------------------------------------------

bool JpegViewer::start(const std::string& title) {
    if (running_) return false;
    title_    = title;
    initDone_ = false;
    initOk_   = false;

    windowThread_ = std::thread(&JpegViewer::windowLoop, this);

    // Wait until the window is created (or fails)
    std::unique_lock<std::mutex> lock(initMutex_);
    initCv_.wait(lock, [this] { return initDone_; });

    return initOk_;
}

void JpegViewer::stop() {
    if (!running_) return;
    running_ = false;
    if (hwnd_) {
        PostMessage(hwnd_, WM_CLOSE, 0, 0);
    }
    if (windowThread_.joinable()) {
        windowThread_.join();
    }
}

void JpegViewer::pushFrame(const uint8_t* jpegData, size_t jpegSize) {
    if (!running_ || !hwnd_ || jpegSize == 0) return;

    {
        std::lock_guard<std::mutex> lock(frameMutex_);
        backBuffer_.assign(jpegData, jpegData + jpegSize);
        isRgbFrame_ = false;
        hasNewFrame_ = true;
    }

    // Signal the window thread to repaint (thread-safe)
    PostMessage(hwnd_, WM_NEW_FRAME, 0, 0);
}

void JpegViewer::pushRgbFrame(const uint8_t* rgbData, int width, int height) {
    if (!running_ || !hwnd_ || !rgbData) return;
    
    size_t size = width * height * 3;
    {
        std::lock_guard<std::mutex> lock(frameMutex_);
        backBuffer_.assign(rgbData, rgbData + size);
        isRgbFrame_ = true;
        rgbWidth_ = width;
        rgbHeight_ = height;
        hasNewFrame_ = true;
    }

    PostMessage(hwnd_, WM_NEW_FRAME, 0, 0);
}

JpegViewer::Stats JpegViewer::stats() const {
    std::lock_guard<std::mutex> lock(statsMutex_);
    return stats_;
}

// ---------------------------------------------------------------------------
//  Window thread
// ---------------------------------------------------------------------------

void JpegViewer::windowLoop() {
    // ---- Initialize GDI+ on this thread ----------------------------------
    Gdiplus::GdiplusStartupInput gdipInput;
    Gdiplus::Status gdipStatus =
        Gdiplus::GdiplusStartup(&gdiplusToken_, &gdipInput, nullptr);

    if (gdipStatus != Gdiplus::Ok) {
        std::cerr << "[JpegViewer] GDI+ startup failed: " << gdipStatus << "\n";
        std::lock_guard<std::mutex> lock(initMutex_);
        initDone_ = true;
        initOk_   = false;
        initCv_.notify_all();
        return;
    }

    // ---- Register window class ------------------------------------------
    HINSTANCE hInst = GetModuleHandle(nullptr);
    WNDCLASSEX wc{};
    wc.cbSize        = sizeof(WNDCLASSEX);
    wc.style         = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc   = wndProcStatic;
    wc.hInstance     = hInst;
    wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    wc.lpszClassName = wndClassName_.c_str();
    RegisterClassEx(&wc);

    // ---- Create window --------------------------------------------------
    RECT rc{0, 0, width_, height_};
    AdjustWindowRect(&rc, WS_OVERLAPPEDWINDOW, FALSE);
    int wndW = rc.right  - rc.left;
    int wndH = rc.bottom - rc.top;

    // Center on screen
    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);
    int posX    = (screenW - wndW) / 2;
    int posY    = (screenH - wndH) / 2;

    hwnd_ = CreateWindowEx(
        0,
        wndClassName_.c_str(),
        title_.c_str(),
        WS_OVERLAPPEDWINDOW,
        posX, posY, wndW, wndH,
        nullptr, nullptr, hInst,
        this  // pass 'this' to WM_NCCREATE
    );

    if (!hwnd_) {
        std::cerr << "[JpegViewer] CreateWindowEx failed: " << GetLastError() << "\n";
        Gdiplus::GdiplusShutdown(gdiplusToken_);
        std::lock_guard<std::mutex> lock(initMutex_);
        initDone_ = true;
        initOk_   = false;
        initCv_.notify_all();
        return;
    }

    ShowWindow(hwnd_, SW_SHOW);
    UpdateWindow(hwnd_);
    running_ = true;

    // Notify main thread that creation succeeded
    {
        std::lock_guard<std::mutex> lock(initMutex_);
        initDone_ = true;
        initOk_   = true;
    }
    initCv_.notify_all();

    // ---- Message loop ---------------------------------------------------
    MSG msg{};
    while (running_ && GetMessage(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    // ---- Cleanup --------------------------------------------------------
    UnregisterClass(wndClassName_.c_str(), hInst);
    Gdiplus::GdiplusShutdown(gdiplusToken_);
    hwnd_ = nullptr;
}

// ---------------------------------------------------------------------------
//  Window procedure (static trampoline)
// ---------------------------------------------------------------------------

LRESULT CALLBACK JpegViewer::wndProcStatic(HWND hwnd, UINT msg,
                                             WPARAM wp, LPARAM lp) {
    JpegViewer* self = nullptr;

    if (msg == WM_NCCREATE) {
        auto* cs = reinterpret_cast<CREATESTRUCT*>(lp);
        self     = reinterpret_cast<JpegViewer*>(cs->lpCreateParams);
        SetWindowLongPtr(hwnd, GWLP_USERDATA,
                         reinterpret_cast<LONG_PTR>(self));
    } else {
        self = reinterpret_cast<JpegViewer*>(
            GetWindowLongPtr(hwnd, GWLP_USERDATA));
    }

    if (self) return self->wndProc(hwnd, msg, wp, lp);
    return DefWindowProc(hwnd, msg, wp, lp);
}

LRESULT JpegViewer::wndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {

    case WM_NEW_FRAME:
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;

    case WM_ERASEBKGND:
        return 1; // We handle background in WM_PAINT → no flicker

    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        onPaint(hdc);
        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_SIZE:
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;

    case WM_CLOSE:
        running_ = false;
        DestroyWindow(hwnd);
        return 0;

    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;

    default:
        return DefWindowProc(hwnd, msg, wp, lp);
    }
}

// ---------------------------------------------------------------------------
//  Rendering
// ---------------------------------------------------------------------------

void JpegViewer::onPaint(HDC hdc) {
    try {
    // Swap buffers if there's a new frame
    std::vector<uint8_t> localData;
    bool isRgb = false;
    int rgbW = 0, rgbH = 0;
    {
        std::lock_guard<std::mutex> lock(frameMutex_);
        if (hasNewFrame_) {
            std::swap(frontBuffer_, backBuffer_);
            hasNewFrame_ = false;
        }
        localData = frontBuffer_; // copy for rendering (avoids holding lock)
        isRgb = isRgbFrame_;
        rgbW = rgbWidth_;
        rgbH = rgbHeight_;
    }

    // Get client area
    RECT clientRect;
    GetClientRect(hwnd_, &clientRect);
    int cw = clientRect.right;
    int ch = clientRect.bottom;

    // Use a memory DC to avoid flicker
    HDC     memDC  = CreateCompatibleDC(hdc);
    HBITMAP memBmp = CreateCompatibleBitmap(hdc, cw, ch);
    HBITMAP oldBmp = static_cast<HBITMAP>(SelectObject(memDC, memBmp));

    // Fill background (black letterbox)
    HBRUSH blackBrush = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    FillRect(memDC, &clientRect, blackBrush);

    if (!localData.empty()) {
        Gdiplus::Bitmap* bmp = nullptr;
        IStream* stream = nullptr;

        if (isRgb) {
            bmp = new Gdiplus::Bitmap(rgbW, rgbH, rgbW * 3, PixelFormat24bppRGB, localData.data());
        } else {
            HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, localData.size());
            if (hMem) {
                void* pMem = GlobalLock(hMem);
                memcpy(pMem, localData.data(), localData.size());
                GlobalUnlock(hMem);

                if (SUCCEEDED(CreateStreamOnHGlobal(hMem, TRUE, &stream))) {
                    bmp = Gdiplus::Bitmap::FromStream(stream);
                }
            }
        }

        if (bmp && bmp->GetLastStatus() == Gdiplus::Ok) {
            int imgW = static_cast<int>(bmp->GetWidth());
            int imgH = static_cast<int>(bmp->GetHeight());

            float scaleX = static_cast<float>(cw) / imgW;
            float scaleY = static_cast<float>(ch) / imgH;
            float scale  = std::min(scaleX, scaleY);

            int drawW = static_cast<int>(imgW * scale);
            int drawH = static_cast<int>(imgH * scale);
            int drawX = (cw - drawW) / 2;
            int drawY = (ch - drawH) / 2;

            Gdiplus::Graphics g(memDC);
            g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
            g.DrawImage(bmp, drawX, drawY, drawW, drawH);

            updateStats(localData.size());

            {
                JpegViewer::Stats s = stats();
                std::wostringstream woss;
                woss << std::fixed << std::setprecision(1)
                     << s.fps << L" FPS  |  "
                     << imgW << L"x" << imgH << L"  |  "
                     << (localData.size() / 1024) << L" KB/frame  |  "
                     << (isRgb ? L"H.264 " : L"JPEG ") << L"Frame #" << s.framesRendered;

                Gdiplus::Font        font(L"Consolas", 11.0f);
                Gdiplus::SolidBrush  bgBrush(Gdiplus::Color(160, 0, 0, 0));
                Gdiplus::SolidBrush  textBrush(Gdiplus::Color(255, 0, 229, 255));

                std::wstring wtext = woss.str();
                Gdiplus::RectF bgRect(5.0f, 5.0f, 420.0f, 22.0f);
                g.FillRectangle(&bgBrush, bgRect);
                g.DrawString(wtext.c_str(), -1, &font, Gdiplus::PointF(10.0f, 7.0f), &textBrush);
            }
        }
        if (bmp) delete bmp;
        if (stream) stream->Release();
    } else {
        Gdiplus::Graphics g(memDC);
        Gdiplus::Font     font(L"Segoe UI", 18.0f);
        Gdiplus::SolidBrush brush(Gdiplus::Color(200, 0, 229, 255));
        std::wstring msg = L"Esperando conexion del telefono...";
        Gdiplus::RectF rect(0.0f, 0.0f, static_cast<float>(cw), static_cast<float>(ch));
        Gdiplus::StringFormat sf;
        sf.SetAlignment(Gdiplus::StringAlignmentCenter);
        sf.SetLineAlignment(Gdiplus::StringAlignmentCenter);
        g.DrawString(msg.c_str(), -1, &font, rect, &sf, &brush);
    }

    BitBlt(hdc, 0, 0, cw, ch, memDC, 0, 0, SRCCOPY);
    SelectObject(memDC, oldBmp);
    DeleteObject(memBmp);
    DeleteDC(memDC);
    } catch (const std::exception& e) {
        std::cerr << "[JpegViewer] EXCEPTION in onPaint: " << e.what() << "\n";
    } catch (...) {
        std::cerr << "[JpegViewer] UNKNOWN EXCEPTION in onPaint\n";
    }
}

// ---------------------------------------------------------------------------
//  Stats
// ---------------------------------------------------------------------------

void JpegViewer::updateStats(size_t frameSize) {
    std::lock_guard<std::mutex> lock(statsMutex_);

    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);

    double elapsed = static_cast<double>(now.QuadPart - lastFrameTime_.QuadPart)
                   / static_cast<double>(perfFreq_.QuadPart);

    if (elapsed > 0.0) {
        // Exponential moving average for FPS
        double instantFps = 1.0 / elapsed;
        stats_.fps = (stats_.fps == 0.0)
                   ? instantFps
                   : stats_.fps * 0.85 + instantFps * 0.15;
    }

    lastFrameTime_ = now;
    stats_.framesRendered++;
    stats_.bytesRendered += frameSize;
}
