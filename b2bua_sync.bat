@echo off
:: =====================================================================
:: b2bua_sync.bat - Universal Dual-Boot / Multi-OS Sync (Windows Side)
:: Synchronizes .env and certificates between Windows and Linux/WSL.
:: =====================================================================
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "WIN_DIR=%SCRIPT_DIR%"
if exist "%SCRIPT_DIR%bin\windows-x64\" set "WIN_DIR=%SCRIPT_DIR%bin\windows-x64\"

echo =====================================================================
echo    JioFiber B2BUA - Multi-Boot Sync Tool (Windows Side)
echo =====================================================================
echo    Current Windows Folder: %WIN_DIR%
echo.

:: 1. Search for WSL distribution paths (e.g. \\wsl$\Ubuntu\home\...\sipserver)
set "WSL_DIR="
for /f "tokens=*" %%D in ('powershell -Command "Get-ChildItem '\\wsl$\' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName"') do (
    for /f "tokens=*" %%U in ('powershell -Command "Get-ChildItem '%%D\home' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName"') do (
        if exist "%%U\sipserver" (
            set "WSL_DIR=%%U\sipserver"
            goto :found_wsl
        )
    )
)

:found_wsl
if defined WSL_DIR (
    echo [*] Detected WSL / Linux Home Folder: %WSL_DIR%
) else (
    echo [i] No active WSL installation found. Syncing between Windows partitions.
)
echo.

echo Options:
echo   1. Push Windows -^> Linux / WSL (Copy .env and certs to Linux)
echo   2. Pull Linux / WSL -^> Windows (Copy .env and certs from Linux)
echo   3. Exit
echo.
set /p "CHOICE=Select an option [1/2/3]: "

if "%CHOICE%"=="1" goto :push
if "%CHOICE%"=="2" goto :pull
if "%CHOICE%"=="3" exit /b
goto :menu

:push
if not defined WSL_DIR (
    echo [ERROR] WSL / Linux path not found.
    pause
    exit /b 1
)
echo.
echo [*] Copying Windows config -^> %WSL_DIR%
if exist "%WIN_DIR%.env" copy /y "%WIN_DIR%.env" "%WSL_DIR%\.env" >nul
if exist "%WIN_DIR%JioFiberB2BUA.*" copy /y "%WIN_DIR%JioFiberB2BUA.*" "%WSL_DIR%\certs\" >nul 2>nul
if exist "%WIN_DIR%cert.*" copy /y "%WIN_DIR%cert.*" "%WSL_DIR%\certs\" >nul 2>nul
if exist "%WIN_DIR%key.*" copy /y "%WIN_DIR%key.*" "%WSL_DIR%\certs\" >nul 2>nul
echo [SUCCESS] Windows configuration pushed to Linux/WSL!
pause
exit /b

:pull
if not defined WSL_DIR (
    echo [ERROR] WSL / Linux path not found.
    pause
    exit /b 1
)
echo.
echo [*] Copying Linux/WSL config -^> %WIN_DIR%
if exist "%WSL_DIR%\.env" copy /y "%WSL_DIR%\.env" "%WIN_DIR%.env" >nul
if exist "%WSL_DIR%\certs\JioFiberB2BUA.*" copy /y "%WSL_DIR%\certs\JioFiberB2BUA.*" "%WIN_DIR%" >nul 2>nul
if exist "%WSL_DIR%\certs\cert.*" copy /y "%WSL_DIR%\certs\cert.*" "%WIN_DIR%" >nul 2>nul
if exist "%WSL_DIR%\certs\key.*" copy /y "%WSL_DIR%\certs\key.*" "%WIN_DIR%" >nul 2>nul
echo [SUCCESS] Linux/WSL configuration pulled into Windows folder!
pause
exit /b
