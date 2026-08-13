@echo off
title Free Ports 5061 and 5062
echo =====================================================================
echo    Terminating processes occupying ports 5061 and 5062
echo =====================================================================
echo.

echo [*] Terminating b2bua instances...
taskkill /F /IM b2bua_msvc.exe >nul 2>&1
taskkill /F /IM b2bua.exe >nul 2>&1

echo [*] Searching netstat for active listeners on ports 5061 / 5062...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":5061 :5062"') do (
    if not "%%a"=="0" (
        echo [*] Killing process PID %%a occupying port...
        taskkill /F /PID %%a >nul 2>&1
    )
)

echo.
echo [*] Done! Ports 5061 and 5062 are now free.
pause
