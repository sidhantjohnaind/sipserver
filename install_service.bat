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

:: Configure Windows Firewall Rules
echo [*] Configuring Windows Firewall rules...
netsh advfirewall firewall delete rule name="JioFiber B2BUA SIP UDP" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA SIP UDP" dir=in action=allow protocol=UDP localport=5061
netsh advfirewall firewall delete rule name="JioFiber B2BUA SIP TLS" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA SIP TLS" dir=in action=allow protocol=TCP localport=5062
netsh advfirewall firewall delete rule name="JioFiber B2BUA RTP Media UDP" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA RTP Media UDP" dir=in action=allow protocol=UDP localport=4000-4050,52000-52200
netsh advfirewall firewall delete rule name="JioFiber B2BUA App" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA App" dir=in action=allow program="%EXE_PATH%" enable=yes
echo [x] Firewall rules applied!
echo.

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
