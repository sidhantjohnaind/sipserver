@echo off
:: =====================================================================
:: uninstall_service.bat - Remove JioFiber B2BUA Windows Startup Task
:: =====================================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] ERROR: Please right-click this script and select "Run as Administrator".
    pause
    exit /b 1
)

echo [*] Removing JioFiber B2BUA Windows Startup Task...
schtasks /Delete /TN "JioFiberB2BUA" /F 2>nul
taskkill /F /IM b2bua_msvc.exe 2>nul

echo [SUCCESS] JioFiber B2BUA Startup Task removed.
pause
