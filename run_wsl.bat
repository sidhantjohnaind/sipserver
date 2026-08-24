@echo off
title JioFiber SIP B2BUA Proxy (WSL Linux)
color 0B

echo =====================================================================
echo    JioFiber SIP Back-to-Back User Agent (WSL Linux Launcher)
echo =====================================================================
echo.

cd /d "%~dp0"

:: Check if WSL is available
wsl --status >nul 2>&1
if errorlevel 1 (
    echo [!] WSL - Windows Subsystem for Linux is not installed or enabled.
    echo [*] Please install WSL by running 'wsl --install' in Administrator PowerShell.
    pause
    exit /b 1
)

echo [*] Terminating any background Windows B2BUA processes...
taskkill /F /IM b2bua_msvc.exe >nul 2>&1

echo [*] Launching B2BUA inside WSL...
echo.

wsl bash -c "chmod +x run_wsl.sh && ./run_wsl.sh"

echo.
echo [*] WSL Session ended.
pause
