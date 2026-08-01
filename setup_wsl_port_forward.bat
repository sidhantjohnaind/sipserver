@echo off
title Setup WSL Mirrored Networking & Port Forwarding
color 0A

echo =====================================================================
echo    Forwarding Windows Wi-Fi Traffic (192.168.29.195:5061) into WSL
echo =====================================================================
echo.

:: Step 1: Create .wslconfig in User Profile for Mirrored Networking Mode
set "WSL_CONFIG=%USERPROFILE%\.wslconfig"

echo [*] Configuring WSL 2 Mirrored Networking Mode in %WSL_CONFIG%...

(
echo [wsl2]
echo networkingMode=mirrored
echo firewall=false
) > "%WSL_CONFIG%"

echo [SUCCESS] Configured Mirrored Networking Mode!
echo.

:: Step 2: Restart WSL to apply Mirrored Networking
echo [*] Restarting WSL service to apply network changes...
wsl --shutdown
timeout /t 2 >nul

echo.
echo =====================================================================
echo [COMPLETE] WSL 2 is now directly bound to your physical network (192.168.29.195).
echo Android phones & Wi-Fi devices can now connect directly to WSL on port 5061!
echo =====================================================================
echo.
pause
