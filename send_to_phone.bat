@echo off
:: =====================================================================
:: send_to_phone.bat - 1-Click Mobile Certificate Delivery Web Server
:: Launches local Python HTTP server on port 8000 for phone download.
:: =====================================================================
setlocal

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

where python >nul 2>&1
if %errorlevel% equ 0 (
    python send_to_phone.py
    goto :done
)

where py >nul 2>&1
if %errorlevel% equ 0 (
    py send_to_phone.py
    goto :done
)

echo [ERROR] Python 3 is not installed or not in PATH.
echo Please install Python 3 from python.org to use the web delivery portal.
pause

:done
