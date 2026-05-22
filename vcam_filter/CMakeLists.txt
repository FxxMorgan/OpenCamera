cmake_minimum_required(VERSION 3.15)
project(CameraLibreVCam)

set(CMAKE_CXX_STANDARD 17)

# Set the output extension to .ax for DirectShow filters
set(CMAKE_SHARED_LIBRARY_SUFFIX ".ax")

# Definition for DLL exports and legacy settings
add_definitions(-D_USRDLL -DDLL_EXPORTS -D_CRT_SECURE_NO_WARNINGS)

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/BaseClasses
)

# DirectShow BaseClasses source files
file(GLOB BASECLASSES_SOURCES "BaseClasses/*.cpp")

# Create static library for BaseClasses
add_library(strmbase STATIC ${BASECLASSES_SOURCES})
target_compile_definitions(strmbase PRIVATE _CRT_SECURE_NO_WARNINGS)

# Source files for the virtual camera filter
set(SOURCES
    src/CameraLibreFilter.cpp
    src/CameraLibreFilter.h
    src/CameraLibreStream.cpp
    src/CameraLibreStream.h
    src/DllSetup.cpp
)

# Create shared library (.ax DirectShow filter)
add_library(${PROJECT_NAME} SHARED ${SOURCES} src/CameraLibreVCam.def)

# Statically link MinGW runtime libraries (libgcc, libstdc++, winpthread).
# This is CRITICAL: the Windows Camera Frame Server (Session 0, LOCAL SERVICE)
# loads our .ax DLL but does NOT have MinGW's bin/ in its PATH.
# Without static linking, LoadLibrary fails → "camera blocked by another app".
target_link_options(${PROJECT_NAME} PRIVATE -static-libgcc -static-libstdc++ -static)

# Link against compiled strmbase and standard Windows SDK libraries
target_link_libraries(${PROJECT_NAME} 
    strmbase
    strmiids.lib 
    kernel32.lib 
    user32.lib 
    gdi32.lib 
    winspool.lib 
    comdlg32.lib 
    advapi32.lib 
    shell32.lib 
    ole32.lib 
    oleaut32.lib 
    uuid.lib 
    odbc32.lib 
    odbccp32.lib
    winmm.lib
)

