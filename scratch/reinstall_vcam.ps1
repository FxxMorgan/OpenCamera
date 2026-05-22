# reinstall_vcam.ps1 — Reinstall virtual camera with FrameServer restart
$ErrorActionPreference = "Stop"

$target = "C:\Program Files\CameraLibre\CameraLibreVCam.ax"
$source = "D:\Programacion\OpenCamera\vcam_filter\build\libCameraLibreVCam.ax"

# 1. Stop the Windows Camera Frame Server to release DLL locks
Write-Host "[1/5] Stopping Windows Camera Frame Server..." -ForegroundColor Yellow
Stop-Service -Name "FrameServer" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "FrameServerMonitor" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# 2. Rename old filter if it exists to release lock
if (Test-Path $target) {
    Write-Host "[2/5] Renaming old filter to release lock..." -ForegroundColor Yellow
    $bakFile = "$target.bak"
    Remove-Item $bakFile -Force -ErrorAction SilentlyContinue
    Rename-Item -Path $target -NewName "CameraLibreVCam.ax.bak" -Force -ErrorAction SilentlyContinue
}

# 3. Copy new filter
Write-Host "[3/5] Copying new statically-linked filter..." -ForegroundColor Cyan
if (-not (Test-Path "C:\Program Files\CameraLibre")) {
    New-Item -ItemType Directory -Path "C:\Program Files\CameraLibre" -Force | Out-Null
}
Copy-Item -Path $source -Destination $target -Force

# 4. Register new filter
Write-Host "[4/5] Registering new filter..." -ForegroundColor Cyan
$regResult = Start-Process "regsvr32.exe" -ArgumentList "/s `"$target`"" -Wait -PassThru -NoNewWindow
if ($regResult.ExitCode -ne 0) {
    Write-Host "WARNING: regsvr32 returned exit code $($regResult.ExitCode)" -ForegroundColor Red
} else {
    Write-Host "  regsvr32 succeeded." -ForegroundColor Green
}

# 5. Restart FrameServer
Write-Host "[5/5] Restarting Windows Camera Frame Server..." -ForegroundColor Yellow
Start-Service -Name "FrameServer" -ErrorAction SilentlyContinue
Start-Service -Name "FrameServerMonitor" -ErrorAction SilentlyContinue

Write-Host "`nDone! The virtual camera filter is now installed with static linking." -ForegroundColor Green
Write-Host "No MinGW runtime DLLs required. FrameServer can load it from Session 0." -ForegroundColor Green
