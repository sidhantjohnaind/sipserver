@echo off
title Install JioFiber B2BUA Windows Service
color 0A

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Please run this script as Administrator (Right click -> Run as Administrator).
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
echo   [SUCCESS] JioFiber B2BUA Windows Service installed & started!
echo   Service Name: JioFiberB2BUA
echo   View Logs:    view_logs.bat
echo =====================================================================
pause
