# build_server.ps1 — Compila el servidor Windows de Cámara Libre
# Uso: .\build_server.ps1

$CMAKE = "A:\msys64\mingw64\bin\cmake.exe"
$SRC   = "$PSScriptRoot\pc_server"
$BUILD = "$PSScriptRoot\pc_server\build"

Write-Host "=== Cámara Libre — Build Servidor PC ===" -ForegroundColor Cyan

# Configure
Write-Host "`n[1/2] Configurando CMake..." -ForegroundColor Yellow
& $CMAKE -S $SRC -B $BUILD `
    -G "MinGW Makefiles" `
    -DCMAKE_CXX_COMPILER="A:\msys64\mingw64\bin\g++.exe" `
    -DCMAKE_BUILD_TYPE=Release

if ($LASTEXITCODE -ne 0) { Write-Host "ERROR en configuración" -ForegroundColor Red; exit 1 }

# Build
Write-Host "`n[2/2] Compilando..." -ForegroundColor Yellow
& $CMAKE --build $BUILD --config Release -j4

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR en compilación" -ForegroundColor Red; exit 1
}

Write-Host "`n✓ Binario en: $PSScriptRoot\pc_server\bin\camera_libre_server.exe" -ForegroundColor Green
Write-Host "  Ejecuta con: .\pc_server\bin\camera_libre_server.exe [puerto]" -ForegroundColor Green
