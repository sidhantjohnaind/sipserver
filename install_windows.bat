@echo off
title JioFiber B2BUA - 1-Click Windows Installer
color 0A

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Administrator privileges required. Elevating...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo =====================================================================
echo    JioFiber SIP B2BUA - 1-Click Windows Installer
echo =====================================================================
echo.

:: 1. Open Firewall Ports
echo [*] Step 1/3: Configuring Windows Firewall rules...
netsh advfirewall firewall delete rule name="JioFiber B2BUA SIP UDP" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA SIP UDP" dir=in action=allow protocol=UDP localport=5061
netsh advfirewall firewall delete rule name="JioFiber B2BUA SIP TLS" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA SIP TLS" dir=in action=allow protocol=TCP localport=5062
netsh advfirewall firewall delete rule name="JioFiber B2BUA RTP Media UDP" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA RTP Media UDP" dir=in action=allow protocol=UDP localport=52000-52200
echo [x] Firewall ports (UDP 5061, TCP 5062, UDP 52000-52200) opened!
echo.

:: 2. Locate Executable
echo [*] Step 2/3: Checking binary executable...
set EXE_PATH=%~dp0bin\windows-x64\b2bua_msvc.exe
if not exist "%EXE_PATH%" (
    set EXE_PATH=%~dp0b2bua_msvc.exe
)

if not exist "%EXE_PATH%" (
    echo [*] Downloading latest release binary from GitHub...
    powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/sidhantjohnaind/sipserver/releases/download/v1.0.0/b2bua_msvc.exe' -OutFile '%~dp0b2bua_msvc.exe'"
    set EXE_PATH=%~dp0b2bua_msvc.exe
)

if not exist "%EXE_PATH%" (
    echo [!] ERROR: Could not locate or download b2bua_msvc.exe
    pause
    exit /b 1
)
echo [x] Found executable at: %EXE_PATH%
echo.

:: 3. Install & Start Windows Service
echo [*] Step 3/3: Registering Windows Service (Auto-Start on Boot)...
taskkill /F /IM b2bua_msvc.exe >nul 2>&1
sc stop JioFiberB2BUA >nul 2>&1
sc delete JioFiberB2BUA >nul 2>&1

sc create JioFiberB2BUA binPath= "\"%EXE_PATH%\"" start= auto DisplayName= "JioFiber SIP B2BUA Service"
sc description JioFiberB2BUA "Lightweight native SIP B2BUA proxy for JioFiber VoIP"
sc start JioFiberB2BUA

echo.
echo =====================================================================
echo   [SUCCESS] JioFiber B2BUA Installed & Running as a Service!
echo   -------------------------------------------------------------------
echo   Service Name: JioFiberB2BUA (Starts automatically on boot)
echo   SIP UDP Port: 5061
echo   SIP TLS Port: 5062
echo   View Logs:    Double click view_logs.bat
echo =====================================================================
echo.
pause
