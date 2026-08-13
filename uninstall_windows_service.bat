@echo off
title Uninstall JioFiber B2BUA Windows Service
color 0C

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Please run this script as Administrator (Right click -> Run as Administrator).
    pause
    exit /b 1
)

cd /d "%~dp0"

echo =====================================================================
echo    Removing JioFiber B2BUA Windows Service
echo =====================================================================
echo.

echo [*] Stopping JioFiberB2BUA service...
sc stop JioFiberB2BUA >nul 2>&1

echo [*] Deleting JioFiberB2BUA service...
sc delete JioFiberB2BUA >nul 2>&1

echo.
echo =====================================================================
echo   [SUCCESS] JioFiber B2BUA Windows Service removed!
echo =====================================================================
pause
