@echo off
:: =====================================================================
:: b2bua_sync.bat - Bare-Metal Multi-Boot Sync Tool (Windows 11 / 10 / Linux)
:: Auto-scans all Windows drive letters (C:, D:, E:, F:, etc.) and shared NTFS
:: partitions to sync .env credentials and certificates across all OSes.
:: =====================================================================
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "SOURCE_DIR=%SCRIPT_DIR%"
if exist "%SCRIPT_DIR%bin\windows-x64\" set "SOURCE_DIR=%SCRIPT_DIR%bin\windows-x64\"

echo =====================================================================
echo    JioFiber B2BUA - Bare-Metal Multi-Boot Sync (Win 11 / 10 / Ubuntu)
echo =====================================================================
echo    Current Active Directory: %SOURCE_DIR%
echo.

:: Detect all potential sipserver locations across all drive letters
set "TARGET_COUNT=0"

for %%D in (C D E F G H I) do (
    if exist "%%D:\" (
        :: Check common installation folders on drive %%D
        for %%P in (
            "%%D:\Programming\sipserver\bin\windows-x64"
            "%%D:\Programming\sipserver"
            "%%D:\sipserver\bin\windows-x64"
            "%%D:\sipserver"
            "%%D:\Program Files\JioFiberB2BUA"
            "%%D:\Program Files (x86)\JioFiberB2BUA"
        ) do (
            if exist "%%~P" (
                if /i not "%%~P"=="%SOURCE_DIR:~0,-1%" if /i not "%%~P\"=="%SOURCE_DIR%" (
                    set /a TARGET_COUNT+=1
                    set "TARGET_!TARGET_COUNT!=%%~P"
                    echo    [!TARGET_COUNT!] Found Target Partition: %%~P
                )
            )
        )
    )
)

echo.
if %TARGET_COUNT% equ 0 (
    echo [i] All files in this folder (%SOURCE_DIR%) are ready for Windows 10/11!
    echo [i] Running b2bua_msvc.exe from this directory directly uses these credentials.
    pause
    exit /b 0
)

echo Available Sync Operations:
echo   1. Push Active Config -^> All Multi-Boot Partitions (Update Win 10 / Win 11 / Shared NTFS)
echo   2. Pull from a Partition -^> Active Directory
echo   3. Exit
echo.
set /p "CHOICE=Select an option [1/2/3]: "

if "%CHOICE%"=="1" goto :push_all
if "%CHOICE%"=="2" goto :pull_select
if "%CHOICE%"=="3" exit /b
exit /b

:push_all
echo.
echo [*] Pushing configuration to all %TARGET_COUNT% partitions...
for /l %%i in (1,1,%TARGET_COUNT%) do (
    set "DEST=!TARGET_%%i!"
    echo    -^> Syncing to: !DEST!
    if exist "%SOURCE_DIR%.env" copy /y "%SOURCE_DIR%.env" "!DEST!\.env" >nul
    if exist "%SOURCE_DIR%JioFiberB2BUA.*" copy /y "%SOURCE_DIR%JioFiberB2BUA.*" "!DEST!\" >nul 2>nul
    if exist "%SOURCE_DIR%cert.*" copy /y "%SOURCE_DIR%cert.*" "!DEST!\" >nul 2>nul
    if exist "%SOURCE_DIR%key.*" copy /y "%SOURCE_DIR%key.*" "!DEST!\" >nul 2>nul
)
echo.
echo [SUCCESS] Multi-boot synchronization complete across all OS drives!
pause
exit /b

:pull_select
echo.
echo Select which partition to copy FROM:
for /l %%i in (1,1,%TARGET_COUNT%) do (
    echo   %%i. !TARGET_%%i!
)
echo.
set /p "PULL_CHOICE=Enter number: "
set "PULL_SRC=!TARGET_%PULL_CHOICE%!"

if not defined PULL_SRC (
    echo [ERROR] Invalid selection.
    pause
    exit /b 1
)

echo.
echo [*] Pulling configuration from %PULL_SRC% -^> %SOURCE_DIR%
if exist "%PULL_SRC%\.env" copy /y "%PULL_SRC%\.env" "%SOURCE_DIR%.env" >nul
if exist "%PULL_SRC%\JioFiberB2BUA.*" copy /y "%PULL_SRC%\JioFiberB2BUA.*" "%SOURCE_DIR%" >nul 2>nul
if exist "%PULL_SRC%\cert.*" copy /y "%PULL_SRC%\cert.*" "%SOURCE_DIR%" >nul 2>nul
if exist "%PULL_SRC%\key.*" copy /y "%PULL_SRC%\key.*" "%SOURCE_DIR%" >nul 2>nul
echo [SUCCESS] Configuration pulled into active directory!
pause
exit /b
