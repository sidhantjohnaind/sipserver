@echo off
:: =====================================================================
:: open_ports_windows.bat - Configure Windows Firewall for JioFiber B2BUA
:: Opens UDP 5061 (SIP) and UDP 4000-4050 (RTP Audio Ports)
:: =====================================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] ERROR: Please right-click this script and select "Run as Administrator".
    pause
    exit /b 1
)

echo [*] Adding Windows Firewall rules for JioFiber B2BUA...

:: Add rule for SIP UDP 5061
netsh advfirewall firewall delete rule name="JioFiber B2BUA SIP UDP" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA SIP UDP" dir=in action=allow protocol=UDP localport=5061

:: Add rule for RTP Audio UDP Ports 4000-4050
netsh advfirewall firewall delete rule name="JioFiber B2BUA RTP Media UDP" 2>nul
netsh advfirewall firewall add rule name="JioFiber B2BUA RTP Media UDP" dir=in action=allow protocol=UDP localport=4000-4050

echo.
echo =====================================================================
echo [SUCCESS] Windows Firewall ports opened successfully!
echo   - Allowed UDP 5061 (SIP Softphone Listener)
echo   - Allowed UDP 4000-4050 (RTP Audio Media Stream Ports)
echo =====================================================================
pause
