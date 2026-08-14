@echo off
:: =====================================================================
:: b2bua_sync.bat - Universal Multi-Boot Sync & Backup Tool (Windows)
:: 
# Works on ANY setup:
# 1. Scans C:\Program Files\JioFiberB2BUA and all drive letters (D:, E:, etc.)
# 2. 1-Click ZIP Archive export/import for USB / Cloud sync
:: =====================================================================
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "SOURCE_DIR=%SCRIPT_DIR%"
if exist "%SCRIPT_DIR%bin\windows-x64\" set "SOURCE_DIR=%SCRIPT_DIR%bin\windows-x64\"

echo =====================================================================
echo    JioFiber B2BUA - Universal Multi-Boot Sync Tool (Windows)
echo =====================================================================
echo    Current Active Directory: %SOURCE_DIR%
echo.

:: 1. Detect all potential sipserver locations across all Windows drive letters (C: to Z:)
set "TARGET_COUNT=0"

for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%D:\" (
        for %%P in (
            "%%D:\Program Files\JioFiberB2BUA"
            "%%D:\Program Files (x86)\JioFiberB2BUA"
            "%%D:\Programming\sipserver\bin\windows-x64"
            "%%D:\Programming\sipserver"
            "%%D:\sipserver\bin\windows-x64"
            "%%D:\sipserver"
            "%%D:\Users\%USERNAME%\sipserver"
            "%%D:\Users\%USERNAME%\Desktop\JioFiber_TLS_Certs"
        ) do (
            if exist "%%~P" (
                if /i not "%%~P"=="%SOURCE_DIR:~0,-1%" if /i not "%%~P\"=="%SOURCE_DIR%" (
                    set /a TARGET_COUNT+=1
                    set "TARGET_!TARGET_COUNT!=%%~P"
                    echo    [!TARGET_COUNT!] Found Windows Partition: %%~P
                )
            )
        )
    )
)

:: 2. Detect WSL Linux Distros (\\wsl$\ and \\wsl.localhost\)
for %%W in ("\\wsl$" "\\wsl.localhost") do (
    if exist "%%~W\" (
        for /f "tokens=*" %%D in ('powershell -Command "Get-ChildItem '%%~W\' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName"') do (
            for /f "tokens=*" %%U in ('powershell -Command "Get-ChildItem '%%D\home' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName"') do (
                if exist "%%U\sipserver" (
                    set /a TARGET_COUNT+=1
                    set "TARGET_!TARGET_COUNT!=%%U\sipserver"
                    echo    [!TARGET_COUNT!] Found WSL Linux Distro: %%U\sipserver
                )
            )
        )
    )
)

echo.
echo Available Sync Operations:
echo   1. Push Active Config -^> All Detected Multi-Boot Partitions
echo   2. Pull from a Location -^> Active Directory
echo   3. Export Portable ZIP Archive (.env + Certs for USB / Backup)
echo   4. Import from Portable ZIP Archive
echo   5. Exit
echo.
set /p "CHOICE=Select an option [1/2/3/4/5]: "

if "%CHOICE%"=="1" goto :push_all
if "%CHOICE%"=="2" goto :pull_select
if "%CHOICE%"=="3" goto :export_zip
if "%CHOICE%"=="4" goto :import_zip
if "%CHOICE%"=="5" exit /b
exit /b

:push_all
if %TARGET_COUNT% equ 0 (
    echo [i] No other partitions found. Use Option 3 to Export a ZIP archive instead!
    pause
    exit /b 0
)
echo.
echo [*] Pushing configuration to all %TARGET_COUNT% locations...
for /l %%i in (1,1,%TARGET_COUNT%) do (
    set "DEST=!TARGET_%%i!"
    echo    -^> Syncing to: !DEST!
    if exist "%SOURCE_DIR%.env" copy /y "%SOURCE_DIR%.env" "!DEST!\.env" >nul
    if exist "%SOURCE_DIR%JioFiberB2BUA.*" copy /y "%SOURCE_DIR%JioFiberB2BUA.*" "!DEST!\" >nul 2>nul
    if exist "%SOURCE_DIR%cert.*" copy /y "%SOURCE_DIR%cert.*" "!DEST!\" >nul 2>nul
    if exist "%SOURCE_DIR%key.*" copy /y "%SOURCE_DIR%key.*" "!DEST!\" >nul 2>nul
)
echo.
echo [SUCCESS] Synchronization complete!
pause
exit /b

:pull_select
if %TARGET_COUNT% equ 0 (
    echo [i] No other partitions found. Use Option 4 to Import from a ZIP archive!
    pause
    exit /b 0
)
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

:export_zip
echo.
set "ZIP_OUT=%USERPROFILE%\Desktop\JioFiber_Config_Backup.zip"
echo [*] Creating portable backup archive: %ZIP_OUT%
powershell -Command "$files = Get-ChildItem -Path '%SOURCE_DIR%' -Include '.env','JioFiberB2BUA.*','cert.*','key.*' -Recurse | Where-Object { -not $_.PSIsContainer }; Compress-Archive -Path $files.FullName -DestinationPath '%ZIP_OUT%' -Force"
echo.
echo [SUCCESS] Exported backup ZIP to Desktop: %ZIP_OUT%
echo You can copy this ZIP to a USB drive or other computer.
pause
exit /b

:import_zip
echo.
set /p "ZIP_IN=Enter full path to ZIP file: "
if not exist "%ZIP_IN%" (
    echo [ERROR] File not found: %ZIP_IN%
    pause
    exit /b 1
)
echo [*] Extracting %ZIP_IN% -^> %SOURCE_DIR%
powershell -Command "Expand-Archive -Path '%ZIP_IN%' -DestinationPath '%SOURCE_DIR%' -Force"
echo.
echo [SUCCESS] Configuration imported successfully!
pause
exit /b
