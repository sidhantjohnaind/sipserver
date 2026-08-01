@echo off
:: =====================================================================
:: install_service.bat - Install JioFiber B2BUA as Windows Startup Task
:: (Runs automatically at Windows Login Screen with 0 SSD writes!)
:: =====================================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] ERROR: Please right-click this script and select "Run as Administrator".
    pause
    exit /b 1
)

set "EXE_PATH=%~dp0bin\windows-x64\b2bua_msvc.exe"

echo [*] Registering JioFiber B2BUA Scheduled Task at Windows Startup...

schtasks /Create /TN "JioFiberB2BUA" /TR "\"%EXE_PATH%\"" /SC ONSTART /RU "SYSTEM" /RL HIGHEST /F

if %errorlevel% equ 0 (
    echo.
    echo =====================================================================
    echo [SUCCESS] JioFiber B2BUA installed as a Windows Startup Task!
    echo It will now run automatically at the Windows Login Screen.
    echo ZERO SSD WRITES: Logs stream in-memory over Windows Named Pipe!
    echo.
    echo To view live logs at any time, run: view_logs.bat
    echo =====================================================================
) else (
    echo [!] Failed to create scheduled task.
)

pause
