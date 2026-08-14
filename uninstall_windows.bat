@echo off
:: =====================================================================
:: uninstall_windows.bat - Complete Clean Uninstaller for Windows
:: Removes Windows Service, Firewall rules, and Root CA Certificates.
:: =====================================================================
setlocal EnableDelayedExpansion
title Uninstall JioFiber B2BUA

:: Check for Administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrator Privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo =====================================================================
echo    JioFiber SIP B2BUA — Windows Uninstaller
echo =====================================================================
echo.

:: 1. Stop & Remove Windows Service
echo [1/3] Stopping and deleting Windows Service...
sc stop JioFiberB2BUA >nul 2>&1
sc delete JioFiberB2BUA >nul 2>&1

:: 2. Remove Windows Defender Firewall Rules
echo [2/3] Cleaning up Windows Firewall rules...
netsh advfirewall firewall delete rule name="JioFiber SIP Server" >nul 2>&1
netsh advfirewall firewall delete rule name="JioFiber SIP Port 5061" >nul 2>&1
netsh advfirewall firewall delete rule name="JioFiber TLS Port 5062" >nul 2>&1
netsh advfirewall firewall delete rule name="JioFiber RTP Audio Ports" >nul 2>&1

:: 3. Remove Root CA Certificate from Store
echo [3/3] Removing Root CA Certificate from Windows store...
certutil -delstore "ROOT" "JioFiberB2BUA" >nul 2>&1

echo.
echo =====================================================================
echo    [SUCCESS] JioFiber B2BUA Windows service & rules removed!
echo =====================================================================
echo.
pause
