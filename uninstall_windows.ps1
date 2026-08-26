# =====================================================================
# JioFiber SIP B2BUA - 1-Click PowerShell Uninstaller
# =====================================================================
# Usage:
#   irm https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/uninstall_windows.ps1 | iex
# =====================================================================

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[*] Requesting Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"& { irm https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/uninstall_windows.ps1 | iex }`"" -Verb RunAs
    exit
}

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "   Uninstalling JioFiber B2BUA Windows Service" -ForegroundColor Yellow
Write-Host "=====================================================================" -ForegroundColor Cyan

Stop-Service -Name "JioFiberB2BUA" -Force -ErrorAction SilentlyContinue
Get-Process -Name "b2bua_msvc", "b2bua" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
cmd.exe /c "taskkill /F /IM b2bua_msvc.exe >nul 2>&1"
cmd.exe /c "sc delete JioFiberB2BUA >nul 2>&1"

cmd.exe /c "netsh advfirewall firewall delete rule name=\"JioFiber B2BUA SIP UDP\" >nul 2>&1"
cmd.exe /c "netsh advfirewall firewall delete rule name=\"JioFiber B2BUA RTP Media UDP\" >nul 2>&1"
cmd.exe /c "netsh advfirewall firewall delete rule name=\"JioFiber B2BUA App\" >nul 2>&1"

Write-Host "[x] Service and Firewall rules removed successfully." -ForegroundColor Green
