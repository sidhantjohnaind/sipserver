@echo off
title JioFiber SIP B2BUA Proxy (Native Windows)
color 0A

echo =====================================================================
echo    JioFiber SIP Back-to-Back User Agent (Native Windows x64)
echo =====================================================================
echo.

:: Change directory to script location
cd /d "%~dp0"

:: Step 1: Locate binary executable
set EXE_PATH=%~dp0bin\windows-x64\b2bua_msvc.exe
if not exist "%EXE_PATH%" set EXE_PATH=%~dp0b2bua_msvc.exe

if not exist "%EXE_PATH%" (
    echo [*] Downloading latest release binary from GitHub...
    powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/sidhantjohnaind/sipserver/releases/download/v1.1.0/b2bua_msvc.exe' -OutFile '%~dp0b2bua_msvc.exe'"
    set EXE_PATH=%~dp0b2bua_msvc.exe
)

if not exist "%EXE_PATH%" (
    echo [!] ERROR: Could not locate b2bua_msvc.exe
    pause
    exit /b 1
)

:: Step 4: Run native Windows B2BUA executable
echo [*] Starting JioFiber B2BUA Proxy...
echo [*] Local Softphone UDP Listener: 192.168.29.195:5061
echo [*] Local Softphone TLS Listener: 192.168.29.195:5062
echo [*] Upstream Jio IMS TLS Target:  192.168.29.1:5068
echo.
echo Press Ctrl+C to stop the proxy.
echo =====================================================================
echo.

bin\windows-x64\b2bua_msvc.exe

echo.
echo [*] B2BUA proxy stopped.
pause
