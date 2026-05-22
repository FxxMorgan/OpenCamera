#pragma once
#include <cstdint>
#include <functional>
#include <string>
#include <thread>
#include <atomic>
#include <vector>
#include "config.hpp"

// Callback type invoked when a complete frame is received
using FrameCallback = std::function<void(const DataFrame&)>;

/**
 * TcpServer - Phase 1
 * Listens on a TCP port, accepts ONE client connection (the phone),
 * reads framed data and fires FrameCallback for each complete frame.
 *
 * Frame wire format (little-endian):
 *   [uint32_t MAGIC = 0x434C4652]
 *   [uint32_t size  = byte length of data]
 *   [uint8_t  data[size]]
 */
class TcpServer {
public:
    explicit TcpServer(uint16_t port = Config::DEFAULT_PORT);
    ~TcpServer();

    // Set the callback before calling start()
    void setFrameCallback(FrameCallback cb);

    // Start listening — blocks until stop() is called from another thread
    bool start();

    // Signal the server to stop accepting/receiving
    void stop();

    // Returns the server's own local IP addresses (for display in UI)
    std::string getLocalIPs() const;

private:
    uint16_t       port_;
    FrameCallback  frameCb_;
    std::atomic<bool> running_{false};

    // Platform socket handle (uintptr_t avoids including winsock here)
    uintptr_t serverSocket_{0};

    void handleClient(uintptr_t clientSocket);
    bool recvAll(uintptr_t sock, uint8_t* buf, uint32_t len);
};
