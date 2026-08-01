@echo off
title JioFiber SIP B2BUA Proxy (Native Windows)
color 0A

echo =====================================================================
echo    JioFiber SIP Back-to-Back User Agent (Native Windows x64)
echo =====================================================================
echo.

:: Change directory to script location
cd /d "%~dp0"

:: Step 1: Check if .env exists
if not exist ".env" (
    echo [!] Configuration file .env not found. Running provisioner...
    python create_env_jfibersip.py
    if errorlevel 1 (
        echo [!] Provisioner failed. Please check network connection to Jio Router.
        pause
        exit /b 1
    )
)

:: Step 2: Stop any stale background instances
echo [*] Terminating any stale b2bua_msvc background processes...
taskkill /F /IM b2bua_msvc.exe >nul 2>&1

:: Step 3: Check if executable exists
if not exist "bin\windows-x64\b2bua_msvc.exe" (
    echo [!] Executable bin\windows-x64\b2bua_msvc.exe not found!
    echo [*] Attempting build with MSVC...
    python src\build_msvc_pjsip.py
)

:: Step 4: Run native Windows B2BUA executable
echo [*] Starting JioFiber B2BUA Proxy...
echo [*] Local Softphone UDP Listener: 192.168.29.195:5061
echo [*] Upstream Jio IMS TLS Target:  192.168.29.1:5068
echo.
echo Press Ctrl+C to stop the proxy.
echo =====================================================================
echo.

bin\windows-x64\b2bua_msvc.exe

echo.
echo [*] B2BUA proxy stopped.
pause
