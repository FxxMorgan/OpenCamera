/**
 * main.cpp — CameraLibre PC Server (Phase 2)
 *
 * What's new vs Phase 1:
 *   - Opens a GDI+ preview window (JpegViewer) in a dedicated thread.
 *   - JPEG frames received from the phone are displayed in real-time.
 *   - Text/ping frames (Phase 1) still work — shown in console.
 *
 * Usage:  camera_libre_server [port] [width] [height]
 *   port    listening port          (default 8080)
 *   width   preview window width    (default 1280)
 *   height  preview window height   (default 720)
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <iostream>
#include <csignal>
#include <atomic>
#include <thread>

#include "tcp_server.hpp"
#include "frame_receiver.hpp"
#include "jpeg_viewer.hpp"
#include "h264_decoder.hpp"
#include "config.hpp"

// ---- Graceful shutdown via Ctrl+C ------------------------------------------

static TcpServer* g_server = nullptr;
static std::atomic<bool> g_running{true};

static BOOL WINAPI ctrlHandler(DWORD type) {
    if (type == CTRL_C_EVENT || type == CTRL_BREAK_EVENT) {
        std::cout << "\n[Main] Shutdown requested...\n";
        g_running = false;
        if (g_server) g_server->stop();
        return TRUE;
    }
    return FALSE;
}

// ---- Main -------------------------------------------------------------------

int main(int argc, char* argv[]) {
    // Banner
    std::cout << "================================================\n";
    std::cout << "  Camara Libre - PC Server  [Phase 3 - H.264/JPEG Stream]\n";
    std::cout << "================================================\n";

    // Parse arguments
    uint16_t port    = Config::DEFAULT_PORT;
    int      viewW   = 1280;
    int      viewH   = 720;

    if (argc >= 2) { try { port  = static_cast<uint16_t>(std::stoi(argv[1])); } catch(...) {} }
    if (argc >= 3) { try { viewW = std::stoi(argv[2]); } catch(...) {} }
    if (argc >= 4) { try { viewH = std::stoi(argv[3]); } catch(...) {} }

    // Setup Ctrl+C handler
    SetConsoleCtrlHandler(ctrlHandler, TRUE);

    // ---- Create preview window (runs in its own thread) --------------------
    JpegViewer viewer(viewW, viewH);
    bool viewerOk = viewer.start("Cámara Libre — Preview");
    if (!viewerOk) {
        std::cerr << "[Main] Warning: Could not open preview window. "
                     "JPEG frames will still be received.\n";
    } else {
        std::cout << "[Main] Preview window opened (" << viewW << "x" << viewH << ")\n";
    }

    // ---- Create server and receiver ----------------------------------------
    TcpServer     server(port);
    FrameReceiver receiver;
    H264Decoder   h264Decoder;

    g_server = &server;

    // Wire JPEG frames → viewer
    if (viewerOk) {
        receiver.setJpegCallback([&viewer](const uint8_t* data, size_t size) {
            viewer.pushFrame(data, size);
        });

        h264Decoder.setRgbCallback([&viewer](const uint8_t* rgbData, int width, int height) {
            viewer.pushRgbFrame(rgbData, width, height);
        });

        receiver.setH264Callback([&h264Decoder](const uint8_t* data, size_t size) {
            h264Decoder.decode(data, size);
        });
    }

    // Wire text frames → console (Phase 1 ping test)
    receiver.setTextCallback([](const std::string& text) {
        (void)text; // already logged inside FrameReceiver
    });

    // Wire all frames → receiver
    server.setFrameCallback([&receiver](const DataFrame& frame) {
        receiver.onFrame(frame);
    });

    // Print connection instructions
    std::cout << "[Main] Listening on port " << port << "\n";
    std::cout << "[Main] Press Ctrl+C to stop.\n";
    std::cout << "[Main] Open 'Camara Libre' on your phone,\n"
              << "       enter this PC's IP + port " << port
              << ", then tap Conectar → Iniciar Streaming.\n\n";

    // Start blocking server loop
    bool ok = server.start();

    // ---- Print session stats -----------------------------------------------
    viewer.stop();

    auto st = receiver.totalFramesReceived();
    auto by = receiver.totalBytesReceived();
    auto vs = viewer.stats();

    std::cout << "\n[Main] Session ended.\n";
    std::cout << "[Main] Frames received  : " << st    << "\n";
    std::cout << "[Main] Bytes  received  : " << by    << "\n";
    std::cout << "[Main] Frames rendered  : " << vs.framesRendered << "\n";
    std::cout << "[Main] Avg FPS (viewer) : " << vs.fps << "\n";

    return ok ? 0 : 1;
}

