@echo off
title Install JioFiber B2BUA Windows Service
color 0A

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Please run this script as Administrator - Right click and select 'Run as Administrator'.
    pause
    exit /b 1
)

cd /d "%~dp0"

echo =====================================================================
echo    Installing JioFiber B2BUA Windows Service
echo =====================================================================
echo.

set EXE_PATH=%~dp0bin\windows-x64\b2bua_msvc.exe

if not exist "%EXE_PATH%" (
    echo [!] Executable not found at %EXE_PATH%
    pause
    exit /b 1
)

:: Configure Windows Firewall Rules
echo [*] Configuring Windows Firewall rules...
netsh advfirewall firewall delete rule name="JioFiber B2BUA SIP UDP" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA SIP UDP" dir=in action=allow protocol=UDP localport=5061
netsh advfirewall firewall delete rule name="JioFiber B2BUA SIP TLS" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA SIP TLS" dir=in action=allow protocol=TCP localport=5062
netsh advfirewall firewall delete rule name="JioFiber B2BUA RTP Media UDP" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA RTP Media UDP" dir=in action=allow protocol=UDP localport=4000-4050,52000-52200
netsh advfirewall firewall delete rule name="JioFiber B2BUA App" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA App" dir=in action=allow program="%EXE_PATH%" enable=yes
echo [x] Firewall rules applied (UDP 5061, TCP 5062, UDP 4000-4050, 52000-52200, Binary)!
echo.

:: Terminate any running processes
taskkill /F /IM b2bua_msvc.exe >nul 2>&1

:: Stop and delete existing service if present
sc stop JioFiberB2BUA >nul 2>&1
sc delete JioFiberB2BUA >nul 2>&1

:: Create Windows Service
sc create JioFiberB2BUA binPath= "\"%EXE_PATH%\"" start= auto DisplayName= "JioFiber SIP B2BUA Service"
sc description JioFiberB2BUA "Lightweight native SIP B2BUA proxy for JioFiber VoIP"
sc failure JioFiberB2BUA reset= 86400 actions= restart/5000/restart/5000/restart/5000
sc start JioFiberB2BUA

echo.
echo =====================================================================
echo   [SUCCESS] JioFiber B2BUA Windows Service installed and started!
echo   Service Name: JioFiberB2BUA
echo   View Logs:    view_logs.bat
echo =====================================================================
pause
