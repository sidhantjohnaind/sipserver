# =====================================================================
# JioFiber SIP B2BUA - 1-Click PowerShell Installer & Service Setup
# =====================================================================
# Usage:
#   irm https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/install_windows.ps1 | iex
# =====================================================================

$ErrorActionPreference = 'Stop'

# Step 1: Self-elevate to Administrator if required
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[*] Requesting Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"& { irm https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/install_windows.ps1 | iex }`"" -Verb RunAs
    exit
}

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "   JioFiber SIP B2BUA - 1-Click Windows Service Installer" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

$installDir = "C:\Program Files\JioFiberB2BUA"
$exePath = Join-Path $installDir "b2bua_msvc.exe"
$releaseUrl = "https://github.com/sidhantjohnaind/sipserver/releases/download/v1.3.0/b2bua_msvc.exe"

# Step 2: Create installation directory
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Write-Host "[x] Created installation directory: $installDir" -ForegroundColor Gray
}

# Step 3: Stop existing service and processes before replacing binary
Write-Host "[*] Stopping existing processes & service..." -ForegroundColor Yellow
Stop-Service -Name "JioFiberB2BUA" -Force -ErrorAction SilentlyContinue
taskkill /F /IM b2bua_msvc.exe 2>$null | Out-Null
Start-Sleep -Seconds 1

# Step 4: Download or copy latest binary
Write-Host "[*] Downloading latest native MSVC binary from GitHub Releases..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
Invoke-WebRequest -Uri $releaseUrl -OutFile $exePath -UseBasicParsing

if (-not (Test-Path $exePath)) {
    Write-Host "[!] ERROR: Failed to download $releaseUrl" -ForegroundColor Red
    exit 1
}
Write-Host "[x] Native binary ready at: $exePath" -ForegroundColor Green

# Step 5: Configure Windows Firewall Rules
Write-Host "[*] Configuring Windows Firewall rules..." -ForegroundColor Cyan
netsh advfirewall firewall delete rule name="JioFiber B2BUA SIP UDP" 2>$null | Out-Null
netsh advfirewall firewall add rule name="JioFiber B2BUA SIP UDP" dir=in action=allow protocol=UDP localport=5061 | Out-Null

netsh advfirewall firewall delete rule name="JioFiber B2BUA RTP Media UDP" 2>$null | Out-Null
netsh advfirewall firewall add rule name="JioFiber B2BUA RTP Media UDP" dir=in action=allow protocol=UDP localport=4000-4050,52000-52200 | Out-Null

netsh advfirewall firewall delete rule name="JioFiber B2BUA App" 2>$null | Out-Null
netsh advfirewall firewall add rule name="JioFiber B2BUA App" dir=in action=allow program="$exePath" enable=yes | Out-Null
Write-Host "[x] Firewall rules configured (UDP 5061, UDP 4000-4050, 52000-52200)!" -ForegroundColor Green

# Step 6: Create and configure Windows Service
Write-Host "[*] Registering JioFiberB2BUA Windows Service..." -ForegroundColor Cyan
sc.exe stop JioFiberB2BUA 2>$null | Out-Null
sc.exe delete JioFiberB2BUA 2>$null | Out-Null

sc.exe create JioFiberB2BUA binPath= "`"$exePath`"" start= auto DisplayName= "JioFiber SIP B2BUA Service" | Out-Null
sc.exe description JioFiberB2BUA "Lightweight native SIP B2BUA proxy for JioFiber VoIP" | Out-Null
sc.exe failure JioFiberB2BUA reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null

# Step 7: Start service
Write-Host "[*] Starting JioFiberB2BUA Service..." -ForegroundColor Cyan
Start-Service -Name "JioFiberB2BUA" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "   [SUCCESS] JioFiber B2BUA Windows Service Installed & Running!" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "   Service Name:   JioFiberB2BUA (Automatic Startup)" -ForegroundColor White
Write-Host "   Check Status:   Get-Service JioFiberB2BUA (or services.msc)" -ForegroundColor White
Write-Host "   Stop Service:   Stop-Service JioFiberB2BUA" -ForegroundColor White
Write-Host "=====================================================================" -ForegroundColor Green
