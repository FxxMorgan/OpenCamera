#pragma once
#include <string>
#include <functional>
#include "config.hpp"

// Callback types for FrameReceiver events
using TextCallback  = std::function<void(const std::string&)>;
using RawCallback   = std::function<void(const DataFrame&)>;
using JpegCallback  = std::function<void(const uint8_t* data, size_t size)>;
using H264Callback  = std::function<void(const uint8_t* data, size_t size)>;

/**
 * FrameReceiver — Phase 1
 * Interprets received DataFrames. For now it just prints them as text
 * and logs frame stats. In Phase 2+ this will decode JPEG/H.264.
 */
class FrameReceiver {
public:
    void onFrame(const DataFrame& frame);

    void setTextCallback(TextCallback cb) { textCb_ = std::move(cb); }
    void setRawCallback(RawCallback   cb) { rawCb_  = std::move(cb); }
    void setJpegCallback(JpegCallback cb) { jpegCb_ = std::move(cb); }
    void setH264Callback(H264Callback cb) { h264Cb_ = std::move(cb); }

    uint64_t totalFramesReceived() const { return frameCount_; }
    uint64_t totalBytesReceived()  const { return byteCount_;  }

private:
    TextCallback  textCb_;
    RawCallback   rawCb_;
    JpegCallback  jpegCb_;
    H264Callback  h264Cb_;
    uint64_t      frameCount_ = 0;
    uint64_t      byteCount_  = 0;

    // Returns true if the frame payload starts with JPEG magic bytes (FF D8 FF)
    static bool isJpeg(const DataFrame& f) {
        return f.size >= 3
            && f.data[0] == 0xFF
            && f.data[1] == 0xD8
            && f.data[2] == 0xFF;
    }

    // Returns true if the frame payload starts with H.264 start code (00 00 00 01 or 00 00 01)
    static bool isH264(const DataFrame& f) {
        if (f.size >= 4 && f.data[0] == 0x00 && f.data[1] == 0x00 && f.data[2] == 0x00 && f.data[3] == 0x01) return true;
        if (f.size >= 3 && f.data[0] == 0x00 && f.data[1] == 0x00 && f.data[2] == 0x01) return true;
        return false;
    }
};
