#include "h264_decoder.hpp"
#include <iostream>
#include <cstdarg>
#include <windows.h>

struct SharedFrameHeader {
    int width;
    int height;
    int frameCount;
    int padding;
};

static void ffmpegLog(void*, int level, const char* fmt, va_list vl) {
    if (level > AV_LOG_WARNING) return;
    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, vl);
    std::cerr << "[FFmpeg] " << buf << "\n";
}

H264Decoder::H264Decoder() {
    static bool logSet = false;
    if (!logSet) {
        av_log_set_callback(ffmpegLog);
        logSet = true;
    }

    codec_ = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (!codec_) {
        std::cerr << "[H264Decoder] Error: H.264 codec not found.\n";
        return;
    }

    codecCtx_ = avcodec_alloc_context3(codec_);
    if (!codecCtx_) {
        std::cerr << "[H264Decoder] Error: Could not allocate codec context.\n";
        return;
    }

    codecCtx_->flags |= AV_CODEC_FLAG_LOW_DELAY;
    codecCtx_->thread_count = 1;

    if (avcodec_open2(codecCtx_, codec_, nullptr) < 0) {
        std::cerr << "[H264Decoder] Error: Could not open codec.\n";
        return;
    }

    frame_    = av_frame_alloc();
    rgbFrame_ = av_frame_alloc();
    packet_   = av_packet_alloc();
}

H264Decoder::~H264Decoder() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (pBuf_) UnmapViewOfFile(pBuf_);
    if (hMapFile_) CloseHandle((HANDLE)hMapFile_);
    if (hFile_) CloseHandle((HANDLE)hFile_);
    if (swsCtx_) sws_freeContext(swsCtx_);
    if (frame_) av_frame_free(&frame_);
    if (rgbFrame_) av_frame_free(&rgbFrame_);
    if (packet_) av_packet_free(&packet_);
    if (codecCtx_) avcodec_free_context(&codecCtx_);
}

void H264Decoder::setRgbCallback(RgbCallback cb) {
    std::lock_guard<std::mutex> lock(mutex_);
    rgbCb_ = std::move(cb);
}

bool H264Decoder::decode(const uint8_t* data, size_t size) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!codecCtx_) return false;

    // Feed raw Annex B stream directly to decoder (no parser needed)
    packet_->data = const_cast<uint8_t*>(data);
    packet_->size = static_cast<int>(size);

    int ret = avcodec_send_packet(codecCtx_, packet_);
    // Unreference the packet to clean up its references/buffers
    av_packet_unref(packet_);

    if (ret < 0) {
        static int sendErrors = 0;
        if (sendErrors++ < 5) {
            char errBuf[256];
            av_strerror(ret, errBuf, sizeof(errBuf));
            std::cerr << "[H264Decoder] send_packet error: " << errBuf << "\n";
        }
        if (sendErrors > 100) {
            avcodec_flush_buffers(codecCtx_);
            sendErrors = 0;
        }
        return true; // continue even on error
    }

    // Drain decoded frames
    static uint64_t decodedCount = 0;
    while (ret >= 0) {
        ret = avcodec_receive_frame(codecCtx_, frame_);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            break;
        }
        if (ret < 0) {
            char errBuf[256];
            av_strerror(ret, errBuf, sizeof(errBuf));
            std::cerr << "[H264Decoder] receive_frame error: " << errBuf << "\n";
            break;
        }
        decodedCount++;
        if (decodedCount % 30 == 0) {
            std::cout << "[H264Decoder] Successfully decoded " << decodedCount << " frames\n";
        }
        processDecodedFrame();
    }

    return true;
}

void H264Decoder::processDecodedFrame() {
    int w = frame_->width;
    int h = frame_->height;

    if (w <= 0 || h <= 0) return;

    const int TARGET_WIDTH = 1280;
    const int TARGET_HEIGHT = 720;

    swsCtx_ = sws_getCachedContext(swsCtx_,
        w, h, static_cast<AVPixelFormat>(frame_->format),
        TARGET_WIDTH, TARGET_HEIGHT, AV_PIX_FMT_BGR24,
        SWS_BILINEAR, nullptr, nullptr, nullptr);

    if (!swsCtx_) {
        std::cerr << "[H264Decoder] Error initializing SwsContext with format: " << frame_->format << "\n";
        return;
    }

    int numBytes = av_image_get_buffer_size(AV_PIX_FMT_BGR24, TARGET_WIDTH, TARGET_HEIGHT, 1);
    if (rgbBuffer_.size() < numBytes) {
        rgbBuffer_.resize(numBytes);
    }

    av_image_fill_arrays(rgbFrame_->data, rgbFrame_->linesize,
                         rgbBuffer_.data(),
                         AV_PIX_FMT_BGR24, TARGET_WIDTH, TARGET_HEIGHT, 1);

    sws_scale(swsCtx_,
              frame_->data, frame_->linesize, 0, h,
              rgbFrame_->data, rgbFrame_->linesize);

    if (rgbCb_) {
        rgbCb_(rgbBuffer_.data(), TARGET_WIDTH, TARGET_HEIGHT);
    }

    // --- File-backed Memory-Mapped IPC ---
    // Uses a physical file at C:\ProgramData\CameraLibre\frame.dat instead of
    // named memory mappings (Global\\/Local\\). This works across all Windows
    // sessions without requiring SeCreateGlobalPrivilege, which is critical
    // because the Windows Camera Frame Server runs in Session 0 as LOCAL SERVICE.
    int numBytesRaw = TARGET_WIDTH * TARGET_HEIGHT * 3;
    size_t requiredSize = sizeof(SharedFrameHeader) + numBytesRaw;

    if (!hMapFile_ || shmSize_ != requiredSize) {
        if (pBuf_) { UnmapViewOfFile(pBuf_); pBuf_ = nullptr; }
        if (hMapFile_) { CloseHandle((HANDLE)hMapFile_); hMapFile_ = nullptr; }
        if (hFile_) { CloseHandle((HANDLE)hFile_); hFile_ = nullptr; }

        shmSize_ = requiredSize;

        // Ensure directory exists
        CreateDirectoryA("C:\\ProgramData\\CameraLibre", NULL);

        // NULL DACL so any user/service can read the file
        SECURITY_DESCRIPTOR sd;
        InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION);
        SetSecurityDescriptorDacl(&sd, TRUE, NULL, FALSE);

        SECURITY_ATTRIBUTES sa;
        sa.nLength = sizeof(sa);
        sa.lpSecurityDescriptor = &sd;
        sa.bInheritHandle = FALSE;

        // Create/open the backing file
        hFile_ = CreateFileA(
            "C:\\ProgramData\\CameraLibre\\frame.dat",
            GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            &sa,
            OPEN_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            NULL);

        if (hFile_ == INVALID_HANDLE_VALUE) {
            std::cerr << "[H264Decoder] Could not create IPC file (" << GetLastError() << ").\n";
            hFile_ = nullptr;
            pBuf_ = nullptr;
        } else {
            // Create memory mapping backed by the file
            hMapFile_ = CreateFileMappingA(
                (HANDLE)hFile_,
                &sa,
                PAGE_READWRITE,
                0,
                static_cast<DWORD>(shmSize_),
                NULL);  // No name needed — both sides open the same file

            if (!hMapFile_) {
                std::cerr << "[H264Decoder] Could not create file mapping (" << GetLastError() << ").\n";
                CloseHandle((HANDLE)hFile_);
                hFile_ = nullptr;
                pBuf_ = nullptr;
            } else {
                pBuf_ = MapViewOfFile(hMapFile_, FILE_MAP_ALL_ACCESS, 0, 0, shmSize_);
                if (!pBuf_) {
                    std::cerr << "[H264Decoder] Could not map view of file (" << GetLastError() << ").\n";
                    CloseHandle((HANDLE)hMapFile_); hMapFile_ = nullptr;
                    CloseHandle((HANDLE)hFile_); hFile_ = nullptr;
                } else {
                    std::cout << "[H264Decoder] File-backed IPC initialized at C:\\ProgramData\\CameraLibre\\frame.dat ("
                              << TARGET_WIDTH << "x" << TARGET_HEIGHT << ")\n";
                }
            }
        }
    }

    if (pBuf_) {
        SharedFrameHeader* header = static_cast<SharedFrameHeader*>(pBuf_);
        header->width = TARGET_WIDTH;
        header->height = TARGET_HEIGHT;
        static int frameCounter = 0;
        header->frameCount = ++frameCounter;

        uint8_t* pixelData = reinterpret_cast<uint8_t*>(header + 1);
        int srcLinesize = rgbFrame_->linesize[0];
        int dstLinesize = TARGET_WIDTH * 3;

        if (srcLinesize == dstLinesize) {
            memcpy(pixelData, rgbFrame_->data[0], dstLinesize * TARGET_HEIGHT);
        } else {
            for (int y = 0; y < TARGET_HEIGHT; ++y) {
                memcpy(pixelData + y * dstLinesize, rgbFrame_->data[0] + y * srcLinesize, dstLinesize);
            }
        }
    }
}

