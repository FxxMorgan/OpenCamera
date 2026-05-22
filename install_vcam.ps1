# install_vcam.ps1
# Requires Administrator privileges

$ErrorActionPreference = "Stop"

# Verify Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Please run this script as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator', then execute this script again."
    Exit
}

$sourceFiles = @(
    (Join-Path $PSScriptRoot "vcam_filter\build\libCameraLibreVCam.ax"),
    (Join-Path $PSScriptRoot "vcam_filter\build\CameraLibreVCam.ax"),
    (Join-Path $PSScriptRoot "vcam_filter\build\Release\CameraLibreVCam.ax"),
    (Join-Path $PSScriptRoot "vcam_filter\build\Debug\CameraLibreVCam.ax"),
    (Join-Path $PSScriptRoot "build\Debug\CameraLibreVCam.ax"),
    (Join-Path $PSScriptRoot "build\Release\CameraLibreVCam.ax"),
    (Join-Path $PSScriptRoot "CameraLibreVCam.ax"),
    (Join-Path $PSScriptRoot "libCameraLibreVCam.ax")
)

$sourceFile = $null
foreach ($file in $sourceFiles) {
    if (Test-Path $file) {
        $sourceFile = $file
        break
    }
}

if ($null -eq $sourceFile) {
    Write-Host "Error: Could not find CameraLibreVCam.ax or libCameraLibreVCam.ax. Please compile the filter first." -ForegroundColor Red
    Exit
}

$installDir = "$env:ProgramFiles\CameraLibre"
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
}

$targetFile = Join-Path $installDir "CameraLibreVCam.ax"

# Unregister if already exists to avoid locking issues
if (Test-Path $targetFile) {
    Write-Host "Unregistering existing filter..." -ForegroundColor Yellow
    Start-Process -FilePath "regsvr32.exe" -ArgumentList "/u /s `"$targetFile`"" -Wait -NoNewWindow
}

Write-Host "Copying filter to $installDir..." -ForegroundColor Cyan
Copy-Item -Path $sourceFile -Destination $targetFile -Force

Write-Host "Registering DirectShow Filter..." -ForegroundColor Cyan
Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s `"$targetFile`"" -Wait -NoNewWindow

Write-Host "Installation Complete! Camera Libre should now appear in OBS, Zoom, etc." -ForegroundColor Green
Write-Host "Note: Do not delete or move the $targetFile file, or the camera will stop working." -ForegroundColor Yellow
