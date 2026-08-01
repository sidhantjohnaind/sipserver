@echo off
title JioFiber SIP Proxy (Windows Native Launcher via WSL)
echo ========================================================
echo         JioFiber SIP Proxy - Windows Launcher
echo ========================================================
echo.

set SCRIPT_DIR=%~dp0
set SCRIPT_DIR_UNIX=%SCRIPT_DIR:\=/%
set SCRIPT_DIR_UNIX=%SCRIPT_DIR_UNIX:D:=/mnt/d%
set SCRIPT_DIR_UNIX=%SCRIPT_DIR_UNIX:C:=/mnt/c%
set SCRIPT_DIR_UNIX=%SCRIPT_DIR_UNIX:E:=/mnt/e%

echo Starting JioFiber SIP Proxy...
wsl -d Debian bash -c "cd '%SCRIPT_DIR_UNIX%' && ./run_native.sh"

pause
