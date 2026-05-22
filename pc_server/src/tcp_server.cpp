/**
 * tcp_server.cpp — Phase 1 implementation
 * Winsock2 TCP server. Accepts one client, reads framed messages.
 */

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <windows.h>

#include <cstring>
#include <iostream>
#include <sstream>
#include <stdexcept>

#include "tcp_server.hpp"

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")

// ---- Helpers ----------------------------------------------------------------

static void wsaCleanup_() {
    WSACleanup();
}

static bool wsaInit() {
    WSADATA wsa;
    int rc = WSAStartup(MAKEWORD(2, 2), &wsa);
    if (rc != 0) {
        std::cerr << "[TcpServer] WSAStartup failed: " << rc << "\n";
        return false;
    }
    return true;
}

// ---- Constructor / Destructor -----------------------------------------------

TcpServer::TcpServer(uint16_t port) : port_(port) {}

TcpServer::~TcpServer() {
    stop();
}

// ---- Public API -------------------------------------------------------------

void TcpServer::setFrameCallback(FrameCallback cb) {
    frameCb_ = std::move(cb);
}

bool TcpServer::start() {
    if (!wsaInit()) return false;

    SOCKET srv = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (srv == INVALID_SOCKET) {
        std::cerr << "[TcpServer] socket() failed: " << WSAGetLastError() << "\n";
        WSACleanup();
        return false;
    }
    serverSocket_ = static_cast<uintptr_t>(srv);

    // Allow quick reuse of the port after restart
    int opt = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR,
               reinterpret_cast<const char*>(&opt), sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_port        = htons(port_);
    addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(srv, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == SOCKET_ERROR) {
        std::cerr << "[TcpServer] bind() failed: " << WSAGetLastError() << "\n";
        closesocket(srv);
        WSACleanup();
        return false;
    }

    if (listen(srv, 1) == SOCKET_ERROR) {
        std::cerr << "[TcpServer] listen() failed: " << WSAGetLastError() << "\n";
        closesocket(srv);
        WSACleanup();
        return false;
    }

    running_ = true;
    std::cout << "[TcpServer] Listening on port " << port_ << "\n";
    std::cout << "[TcpServer] Local IPs: " << getLocalIPs() << "\n";
    std::cout << "[TcpServer] Waiting for mobile device to connect...\n";

    // Phase 1: accept one client at a time (blocking loop)
    while (running_) {
        sockaddr_in clientAddr{};
        int clientLen = sizeof(clientAddr);

        // Use select() with a timeout so we can check running_ periodically
        fd_set readSet;
        FD_ZERO(&readSet);
        FD_SET(srv, &readSet);
        timeval tv{1, 0}; // 1 second timeout

        int ready = select(0, &readSet, nullptr, nullptr, &tv);
        if (ready == SOCKET_ERROR) {
            if (running_) {
                std::cerr << "[TcpServer] select() error: " << WSAGetLastError() << "\n";
            }
            break;
        }
        if (ready == 0) continue; // timeout — loop and check running_

        SOCKET client = accept(srv,
                               reinterpret_cast<sockaddr*>(&clientAddr),
                               &clientLen);
        if (client == INVALID_SOCKET) {
            if (running_) {
                std::cerr << "[TcpServer] accept() failed: " << WSAGetLastError() << "\n";
            }
            continue;
        }

        char clientIp[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &clientAddr.sin_addr, clientIp, sizeof(clientIp));
        std::cout << "[TcpServer] Client connected from " << clientIp << "\n";

        handleClient(static_cast<uintptr_t>(client));

        closesocket(client);
        std::cout << "[TcpServer] Client disconnected. Waiting for next connection...\n";
    }

    closesocket(srv);
    WSACleanup();
    return true;
}

void TcpServer::stop() {
    running_ = false;
    // Closing the server socket unblocks accept()
    if (serverSocket_ != 0) {
        closesocket(static_cast<SOCKET>(serverSocket_));
        serverSocket_ = 0;
    }
}

std::string TcpServer::getLocalIPs() const {
    std::ostringstream oss;
    char hostname[256];
    if (gethostname(hostname, sizeof(hostname)) == 0) {
        addrinfo hints{};
        hints.ai_family   = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        addrinfo* res = nullptr;
        if (getaddrinfo(hostname, nullptr, &hints, &res) == 0) {
            for (addrinfo* p = res; p != nullptr; p = p->ai_next) {
                char ip[INET_ADDRSTRLEN];
                auto* sin = reinterpret_cast<sockaddr_in*>(p->ai_addr);
                inet_ntop(AF_INET, &sin->sin_addr, ip, sizeof(ip));
                if (oss.tellp() > 0) oss << ", ";
                oss << ip;
            }
            freeaddrinfo(res);
        }
    }
    return oss.str().empty() ? "unknown" : oss.str();
}

// ---- Private Helpers --------------------------------------------------------

bool TcpServer::recvAll(uintptr_t sock, uint8_t* buf, uint32_t len) {
    SOCKET s    = static_cast<SOCKET>(sock);
    uint32_t got = 0;
    while (got < len && running_) {
        int n = recv(s,
                     reinterpret_cast<char*>(buf + got),
                     static_cast<int>(len - got),
                     0);
        if (n <= 0) return false; // disconnected or error
        got += static_cast<uint32_t>(n);
    }
    return got == len;
}

void TcpServer::handleClient(uintptr_t clientSocket) {
    // Read frames: [MAGIC:4][SIZE:4][DATA:SIZE]
    while (running_) {
        try {
            uint32_t header[2]; // [magic, size]

            if (!recvAll(clientSocket,
                         reinterpret_cast<uint8_t*>(header),
                         sizeof(header))) {
                break;
            }

            uint32_t magic = header[0];
            uint32_t size  = header[1];

            if (magic != Config::FRAME_MAGIC) {
                std::cerr << "[TcpServer] Bad magic: 0x" << std::hex << magic << std::dec << "\n";
                break; // corrupt stream, disconnect
            }

            if (size == 0 || size > Config::MAX_FRAME_SIZE) {
                std::cerr << "[TcpServer] Invalid frame size: " << size << "\n";
                break;
            }

            DataFrame frame;
            frame.size = size;
            frame.data.resize(size);

            if (!recvAll(clientSocket, frame.data.data(), size)) {
                break;
            }

            if (frameCb_) {
                frameCb_(frame);
            }
        } catch (const std::exception& e) {
            std::cerr << "[TcpServer] EXCEPTION in handleClient: " << e.what() << "\n";
            break;
        } catch (...) {
            std::cerr << "[TcpServer] UNKNOWN EXCEPTION in handleClient\n";
            break;
        }
    }
}
