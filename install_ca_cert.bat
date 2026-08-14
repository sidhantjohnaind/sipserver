@echo off
:: =====================================================================
:: install_ca_cert.bat - 1-Click Windows CA Certificate Trust Installer
:: Installs JioFiberB2BUA certificate into "Trusted Root Certification Authorities"
:: =====================================================================
setlocal EnableDelayedExpansion

:: Check for Administrator permissions
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrator Privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set "SCRIPT_DIR=%~dp0"
set "CERT_FILE="

:: Locate the certificate file
if exist "%SCRIPT_DIR%JioFiberB2BUA.crt" set "CERT_FILE=%SCRIPT_DIR%JioFiberB2BUA.crt"
if not defined CERT_FILE if exist "%SCRIPT_DIR%certs\JioFiberB2BUA.crt" set "CERT_FILE=%SCRIPT_DIR%certs\JioFiberB2BUA.crt"
if not defined CERT_FILE if exist "%SCRIPT_DIR%cert.crt" set "CERT_FILE=%SCRIPT_DIR%cert.crt"
if not defined CERT_FILE if exist "%SCRIPT_DIR%certs\cert.crt" set "CERT_FILE=%SCRIPT_DIR%certs\cert.crt"
if not defined CERT_FILE if exist "%SCRIPT_DIR%JioFiberB2BUA.pem" set "CERT_FILE=%SCRIPT_DIR%JioFiberB2BUA.pem"

if not defined CERT_FILE (
    echo [ERROR] Certificate file (JioFiberB2BUA.crt / cert.crt) not found!
    echo Please ensure certificate files exist in this folder.
    pause
    exit /b 1
)

echo =====================================================================
echo    Installing CA Certificate into Windows Trusted Root Store
echo    Source: %CERT_FILE%
echo =====================================================================
echo.

:: Add to Windows System Root Store (LocalMachine & CurrentUser)
certutil -addstore -f "ROOT" "%CERT_FILE%"
if %errorlevel% equ 0 (
    echo.
    echo =====================================================================
    echo    [SUCCESS] JioFiberB2BUA CA Certificate installed successfully!
    echo    All Windows browsers (Edge, Chrome), apps, and services
    echo    will now trust HTTPS and TLS connections on your LAN without warnings.
    echo =====================================================================
) else (
    echo.
    echo [ERROR] Failed to install certificate with certutil.
)

echo.
pause
