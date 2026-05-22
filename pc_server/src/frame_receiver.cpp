/**
 * frame_receiver.cpp — Phase 1
 * Processes incoming frames: for now just echoes text content and prints stats.
 * Phase 2 will add JPEG decoding, Phase 3 H.264.
 */
#include "frame_receiver.hpp"
#include <iostream>
#include <chrono>
#include <iomanip>

void FrameReceiver::onFrame(const DataFrame& frame) {
    ++frameCount_;
    byteCount_ += frame.size;

    // Fire raw callback always
    if (rawCb_) rawCb_(frame);

    // ---- Detect payload type ------------------------------------------------
    if (isH264(frame)) {
        // Phase 3: H.264 video frame -> send to H.264 decoder
        if (h264Cb_) h264Cb_(frame.data.data(), frame.size);

        if (frameCount_ % 30 == 0) {
            auto now = std::chrono::system_clock::now();
            auto tt  = std::chrono::system_clock::to_time_t(now);
            std::tm tmBuf;
            localtime_s(&tmBuf, &tt);
            std::cout << std::put_time(&tmBuf, "[%H:%M:%S]")
                      << " H264 frame #" << frameCount_
                      << " | " << (frame.size / 1024) << " KB\n";
        }
    } else if (isJpeg(frame)) {
        // Phase 2: JPEG image frame → send to viewer
        if (jpegCb_) jpegCb_(frame.data.data(), frame.size);

        // Console: only print stats every 30 frames to avoid flooding
        if (frameCount_ % 30 == 0) {
            auto now = std::chrono::system_clock::now();
            auto tt  = std::chrono::system_clock::to_time_t(now);
            std::tm tmBuf;
            localtime_s(&tmBuf, &tt);
            std::cout << std::put_time(&tmBuf, "[%H:%M:%S]")
                      << " JPEG frame #" << frameCount_
                      << " | " << (frame.size / 1024) << " KB\n";
        }
    } else {
        // Phase 1: text/ping frame → log to console
        // Safety: cap string conversion to avoid std::length_error on large payloads
        constexpr size_t kMaxTextSize = 4096;
        size_t textSize = (frame.size < kMaxTextSize) ? frame.size : kMaxTextSize;
        std::string text(frame.data.begin(), frame.data.begin() + static_cast<ptrdiff_t>(textSize));
        if (textCb_) textCb_(text);

        auto now = std::chrono::system_clock::now();
        auto tt  = std::chrono::system_clock::to_time_t(now);
        std::tm tmBuf;
        localtime_s(&tmBuf, &tt);
        std::cout << std::put_time(&tmBuf, "[%H:%M:%S]")
                  << " Text/Unknown frame #" << frameCount_
                  << " | " << frame.size << " bytes"
                  << " | \"" << text.substr(0, 80)
                  << (textSize > 80 ? "..." : "")
                  << "\"\n";
    }
}
