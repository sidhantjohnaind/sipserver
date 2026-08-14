@echo off
title JioFiber B2BUA - Open TLS Certificate Location
cd /d "%~dp0"

set "CERTS_DIR=%~dp0certs"

if not exist "%CERTS_DIR%" (
    if exist "%ProgramFiles%\JioFiberB2BUA\certs" (
        set "CERTS_DIR=%ProgramFiles%\JioFiberB2BUA\certs"
    ) else (
        mkdir "%CERTS_DIR%" 2>nul
        copy "%~dp0cert.pem" "%CERTS_DIR%\" >nul 2>&1
        copy "%~dp0key.pem" "%CERTS_DIR%\" >nul 2>&1
    )
)

if exist "%CERTS_DIR%" (
    echo [*] Opening TLS certificates folder in Explorer...
    explorer.exe "%CERTS_DIR%"
) else (
    echo [*] Opening application folder in Explorer...
    explorer.exe "%~dp0"
)
