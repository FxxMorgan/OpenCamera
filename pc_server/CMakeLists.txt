cmake_minimum_required(VERSION 3.15)
project(CameraLibreServer VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Windows-specific: link against Winsock2
if(WIN32)
    set(PLATFORM_LIBS ws2_32)
endif()

add_executable(camera_libre_server
    src/main.cpp
    src/tcp_server.cpp
    src/frame_receiver.cpp
    src/jpeg_viewer.cpp
    src/h264_decoder.cpp
)

target_include_directories(camera_libre_server PRIVATE src)

# GDI+ and OLE are part of the Windows SDK — no external install needed
if(WIN32)
    list(APPEND PLATFORM_LIBS gdiplus ole32)
endif()

# Find FFmpeg using pkg-config
find_package(PkgConfig REQUIRED)
pkg_check_modules(FFMPEG REQUIRED libavcodec libavformat libavutil libswscale)

target_include_directories(camera_libre_server PRIVATE src ${FFMPEG_INCLUDE_DIRS})
target_link_libraries(camera_libre_server PRIVATE ${PLATFORM_LIBS} ${FFMPEG_LIBRARIES})

# Copy executable to a convenient location after build
set_target_properties(camera_libre_server PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin"
)

message(STATUS "CameraLibreServer configured for Windows (Winsock2)")
