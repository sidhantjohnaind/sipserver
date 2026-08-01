# JioFiber SIP Proxy - Windows PowerShell Launcher
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UnixPath = $ScriptDir -replace '\\', '/' -replace '([A-Za-z]):', '/mnt/$1' | ForEach-Object { $_.ToLower() }

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "        JioFiber SIP Proxy - Windows Launcher           " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Starting SIP Proxy in background..." -ForegroundColor Green

wsl -d Debian bash -c "cd '$UnixPath' && ./run_native.sh"
