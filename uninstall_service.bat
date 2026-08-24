@echo off
:: =====================================================================
:: uninstall_service.bat - Remove JioFiber B2BUA Windows Startup Task
:: =====================================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] ERROR: Please right-click this script and select "Run as Administrator".
    pause
    exit /b 1
)

echo [*] Removing JioFiber B2BUA Windows Startup Task...
schtasks /Delete /TN "JioFiberB2BUA" /F 2>nul
taskkill /F /IM b2bua_msvc.exe 2>nul

echo [*] Removing Windows Firewall rules...
netsh advfirewall firewall delete rule name="JioFiber B2BUA SIP UDP" 2>nul
netsh advfirewall firewall delete rule name="JioFiber B2BUA SIP TLS" 2>nul
netsh advfirewall firewall delete rule name="JioFiber B2BUA RTP Media UDP" 2>nul
netsh advfirewall firewall delete rule name="JioFiber B2BUA App" 2>nul

echo [SUCCESS] JioFiber B2BUA Startup Task and Firewall rules removed.
pause
