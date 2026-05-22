#pragma once
#include <string>
#include <cstdint>
#include <vector>

// Configuration constants for Phase 1
namespace Config {
    constexpr uint16_t DEFAULT_PORT = 8080;
    constexpr int      MAX_CONNECTIONS = 1;
    constexpr int      RECV_BUFFER_SIZE = 65536; // 64 KB
    constexpr int      MAX_FRAME_SIZE = 1024 * 1024 * 10; // 10 MB max frame

    // Frame protocol constants
    // Simple frame format: [MAGIC:4][SIZE:4][DATA:SIZE]
    constexpr uint32_t FRAME_MAGIC = 0x434C4652; // "CLFR" (CameraLibre FRame)
}

// Represents a received raw data frame (Phase 1: just bytes)
struct DataFrame {
    uint32_t size   = 0;
    std::vector<uint8_t> data;
};
