# =====================================================================
# JioFiber SIP B2BUA - 1-Click PowerShell Installer & Service Setup
# =====================================================================
# Usage:
#   irm https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/install_windows.ps1 | iex
# =====================================================================

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

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
Get-Process -Name "b2bua_msvc", "b2bua" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
cmd.exe /c "taskkill /F /IM b2bua_msvc.exe >nul 2>&1"
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

# Download view_logs.bat helper
$viewLogsUrl = "https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/view_logs.bat"
Invoke-WebRequest -Uri $viewLogsUrl -OutFile (Join-Path $installDir "view_logs.bat") -UseBasicParsing -ErrorAction SilentlyContinue

# Step 4.5: Check for .env or run one-time OTP Provisioner
$envPath = Join-Path $installDir ".env"
if (-not (Test-Path $envPath)) {
    if (Test-Path ".\.env") {
        Copy-Item ".\.env" $envPath -Force
        Write-Host "[x] Copied existing .env configuration to $envPath" -ForegroundColor Green
    } elseif (Test-Path "$HOME\.jio_b2bua.env") {
        Copy-Item "$HOME\.jio_b2bua.env" $envPath -Force
        Write-Host "[x] Copied existing .env from user profile to $envPath" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "---------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "   [!] ONE-TIME SETUP: Jio Router OTP Provisioning Required" -ForegroundColor Yellow
        Write-Host "---------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "   A console window will now open to request OTP from your Jio Router." -ForegroundColor White
        Write-Host "   1. Enter your Jio Router IP (press Enter for default 192.168.29.1)." -ForegroundColor White
        Write-Host "   2. Enter the OTP sent to your registered mobile number." -ForegroundColor White
        Write-Host "---------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host ""
        Start-Process -FilePath "$exePath" -ArgumentList "--console" -Wait -WorkingDirectory "$installDir"
    }
}

# Step 5: Configure Windows Firewall Rules
Write-Host "[*] Configuring Windows Firewall rules..." -ForegroundColor Cyan
cmd.exe /c "netsh advfirewall firewall delete rule name=\"JioFiber B2BUA SIP UDP\" >nul 2>&1"
cmd.exe /c "netsh advfirewall firewall add rule name=\"JioFiber B2BUA SIP UDP\" dir=in action=allow protocol=UDP localport=5061 >nul 2>&1"

cmd.exe /c "netsh advfirewall firewall delete rule name=\"JioFiber B2BUA RTP Media UDP\" >nul 2>&1"
cmd.exe /c "netsh advfirewall firewall add rule name=\"JioFiber B2BUA RTP Media UDP\" dir=in action=allow protocol=UDP localport=4000-4050,52000-52200 >nul 2>&1"

cmd.exe /c "netsh advfirewall firewall delete rule name=\"JioFiber B2BUA App\" >nul 2>&1"
cmd.exe /c "netsh advfirewall firewall add rule name=\"JioFiber B2BUA App\" dir=in action=allow program=\"$exePath\" enable=yes >nul 2>&1"
Write-Host "[x] Firewall rules configured (UDP 5061, UDP 4000-4050, 52000-52200)!" -ForegroundColor Green

# Step 6: Create and configure Windows Service
Write-Host "[*] Registering JioFiberB2BUA Windows Service..." -ForegroundColor Cyan
Stop-Service -Name "JioFiberB2BUA" -Force -ErrorAction SilentlyContinue
& sc.exe delete JioFiberB2BUA 2>$null | Out-Null
Start-Sleep -Seconds 1

try {
    New-Service -Name "JioFiberB2BUA" -BinaryPathName "`"$exePath`"" -DisplayName "JioFiber SIP B2BUA Service" -StartupType Automatic -Description "Lightweight native SIP B2BUA proxy for JioFiber VoIP" -ErrorAction Stop | Out-Null
    Write-Host "[x] Windows Service registered via New-Service!" -ForegroundColor Green
} catch {
    & sc.exe create JioFiberB2BUA binPath= "`"$exePath`"" start= auto DisplayName= "JioFiber SIP B2BUA Service" | Out-Null
    & sc.exe description JioFiberB2BUA "Lightweight native SIP B2BUA proxy for JioFiber VoIP" | Out-Null
}
& sc.exe failure JioFiberB2BUA reset= 86400 actions= restart/5000/restart/5000/restart/5000 2>$null | Out-Null

# Step 7: Start service
Write-Host "[*] Starting JioFiberB2BUA Service..." -ForegroundColor Cyan
Start-Service -Name "JioFiberB2BUA" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "   [SUCCESS] JioFiber B2BUA Windows Service Installed & Running!" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host "   Service Name:   JioFiberB2BUA (Automatic Startup)" -ForegroundColor White
Write-Host "   Install Dir:    $installDir" -ForegroundColor White
Write-Host "   View Logs:      & '$installDir\view_logs.bat'" -ForegroundColor Yellow
Write-Host "   Check Status:   Get-Service JioFiberB2BUA (or services.msc)" -ForegroundColor White
Write-Host "   Stop Service:   Stop-Service JioFiberB2BUA" -ForegroundColor White
Write-Host "=====================================================================" -ForegroundColor Green
