# =====================================================================
# JioFiber SIP B2BUA - 1-Click PowerShell Uninstaller
# =====================================================================
# Usage:
#   irm https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/uninstall_windows.ps1 | iex
# =====================================================================

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
taskkill /F /IM b2bua_msvc.exe 2>$null | Out-Null
sc.exe delete JioFiberB2BUA 2>$null | Out-Null

netsh advfirewall firewall delete rule name="JioFiber B2BUA SIP UDP" 2>$null | Out-Null
netsh advfirewall firewall delete rule name="JioFiber B2BUA RTP Media UDP" 2>$null | Out-Null
netsh advfirewall firewall delete rule name="JioFiber B2BUA App" 2>$null | Out-Null

Write-Host "[x] Service and Firewall rules removed successfully." -ForegroundColor Green
