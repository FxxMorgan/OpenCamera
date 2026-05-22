#pragma once

#include <vector>
#include <cstdint>
#include <functional>
#include <mutex>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
}

// Callback when a frame is decoded to RGB24 (BGR format for Windows GDI)
using RgbCallback = std::function<void(const uint8_t* rgbData, int width, int height)>;

class H264Decoder {
public:
    H264Decoder();
    ~H264Decoder();

    void setRgbCallback(RgbCallback cb);
    
    // Decode an H.264 chunk (can be a NAL unit or a chunk of stream).
    // Returns true if processing was successful (even if no frame was produced yet).
    bool decode(const uint8_t* data, size_t size);

private:
    const AVCodec*  codec_    = nullptr;
    AVCodecContext* codecCtx_ = nullptr;
    AVFrame*        frame_    = nullptr;
    AVFrame*        rgbFrame_ = nullptr;
    AVPacket*       packet_   = nullptr;
    SwsContext*     swsCtx_   = nullptr;

    RgbCallback     rgbCb_;
    std::mutex      mutex_;
    std::vector<uint8_t> rgbBuffer_;

    void processDecodedFrame();

    void* hFile_    = nullptr;  // Backing file handle for IPC
    void* hMapFile_ = nullptr;
    void* pBuf_ = nullptr;
    size_t shmSize_ = 0;
};
