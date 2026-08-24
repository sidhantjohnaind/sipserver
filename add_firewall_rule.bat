@echo off
title JioFiber SIP Proxy Firewall Configurator
color 0B

echo =====================================================================
echo    Allowing JioFiber SIP Proxy Ports in Windows Defender Firewall
echo =====================================================================
echo.

:: Check for Administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Administrator privileges required!
    echo [*] Please right-click 'add_firewall_rule.bat' and select 'Run as administrator'.
    echo.
    pause
    exit /b 1
)

echo [*] Adding Inbound Firewall Rules for UDP/TCP Port 5061, 5062 & TLS Port 5068...
powershell -Command "New-NetFirewallRule -DisplayName 'Jio B2BUA UDP 5061' -Direction Inbound -LocalPort 5061 -Protocol UDP -Action Allow -ErrorAction SilentlyContinue"
powershell -Command "New-NetFirewallRule -DisplayName 'Jio B2BUA TCP 5061' -Direction Inbound -LocalPort 5061 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue"
powershell -Command "New-NetFirewallRule -DisplayName 'Jio B2BUA UDP 5062' -Direction Inbound -LocalPort 5062 -Protocol UDP -Action Allow -ErrorAction SilentlyContinue"
powershell -Command "New-NetFirewallRule -DisplayName 'Jio B2BUA Executable' -Direction Inbound -Program '%~dp0bin\windows-x64\b2bua_msvc.exe' -Action Allow -ErrorAction SilentlyContinue"

echo.
echo [SUCCESS] Windows Defender Firewall rules added successfully!
echo [*] Android SIP devices on Wi-Fi can now connect without IO Errors.
echo.
pause
