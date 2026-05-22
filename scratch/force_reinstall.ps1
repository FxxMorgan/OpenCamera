$ErrorActionPreference = "Stop"

$target = "C:\Program Files\CameraLibre\CameraLibreVCam.ax"
$source = "D:\Programacion\OpenCamera\vcam_filter\build\libCameraLibreVCam.ax"

Write-Host "[1/6] Stopping FrameServer..." -ForegroundColor Yellow
Stop-Service -Name "FrameServerMonitor" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "FrameServer" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "[2/6] Checking FrameServer state..." -ForegroundColor Yellow
$svc = Get-Service FrameServer
Write-Host "  FrameServer status: $($svc.Status)"

Write-Host "[3/6] Skipping unregistration to avoid deadlock..." -ForegroundColor Yellow
# if (Test-Path $target) {
#     $p = Start-Process regsvr32.exe -ArgumentList "/u /s `"$target`"" -Wait -PassThru -NoNewWindow
#     Write-Host "  regsvr32 /u exit: $($p.ExitCode)"
#     Start-Sleep -Seconds 1
# }


Write-Host "[4/6] Checking if file is locked..." -ForegroundColor Yellow
try {
    $stream = [System.IO.File]::Open($target, 'Open', 'ReadWrite', 'None')
    $stream.Close()
    Write-Host "  File is NOT locked" -ForegroundColor Green
} catch {
    Write-Host "  File IS locked: $_" -ForegroundColor Red
    Write-Host "  Trying to rename instead..." -ForegroundColor Yellow
    $bak = "$target.bak"
    Remove-Item $bak -Force -ErrorAction SilentlyContinue
    Rename-Item $target $bak -Force -ErrorAction SilentlyContinue
}

Write-Host "[5/6] Copying new filter..." -ForegroundColor Cyan
Copy-Item -Path $source -Destination $target -Force
$newLen = (Get-Item $target).Length
$srcLen = (Get-Item $source).Length
Write-Host "  Source: $srcLen bytes, Installed: $newLen bytes"
if ($newLen -eq $srcLen) {
    Write-Host "  SIZE MATCH OK" -ForegroundColor Green
} else {
    Write-Host "  SIZE MISMATCH!" -ForegroundColor Red
}

Write-Host "[6/6] Registering + starting FrameServer..." -ForegroundColor Yellow
$p = Start-Process regsvr32.exe -ArgumentList "/s `"$target`"" -Wait -PassThru -NoNewWindow
Write-Host "  regsvr32 exit: $($p.ExitCode)"
Start-Service FrameServer
Start-Service FrameServerMonitor -ErrorAction SilentlyContinue
Write-Host "  FrameServer: $((Get-Service FrameServer).Status)"

Write-Host "`nDone!" -ForegroundColor Green
