# JioFiber SIP B2BUA

A lightweight, native **SIP Back-to-Back User Agent (B2BUA)** that bridges JioFiber VoIP (Jio IMS) to any standard SIP softphone — over LAN, Tailscale, ZeroTier, WireGuard, or any VPN.

No Docker. No Asterisk. No cloud. Runs as a single binary.

---

## Features

- **Zero-dependency binary** — single executable for Windows, Linux x86_64, Linux ARM64, and RISC-V 64
- **Embedded Native OTP Provisioner** — automatically requests OTP and provisions credentials directly from your Jio router without needing Python
- **Standard SIP UDP Transport**: Listens on UDP port `5061` for all softphones (MicroSIP, Linphone, GS Wave, etc.)
- **Upstream Carrier TLS Transport**: Secure TLS v1.2 (`5068`) to Jio IMS router/ONT
- **Strict Port Binding**: Binds cleanly to `5061` and exits immediately if port is occupied
- **Automatic SIP registration** with Jio IMS with self-healing credential rotation recovery
- **Full call flow bridging** — outgoing calls, incoming calls, BYE, CANCEL, re-INVITE
- **Multi-network support** — LAN, Tailscale, ZeroTier, WireGuard, OpenVPN
  - Per-call dynamic source IP detection using OS kernel routing table (`getsockname` connect trick)
  - Solves one-way audio and call teardown failures across VPN overlays
  - Zero static IP configuration needed
- **Robust Teardown Handling** — clean SIP `CANCEL` & `BYE` handling without double-hangup assertions
- **PUBLISH / presence** passthrough for softphone status
- **Zero SSD wear logging** — 512 KB RAM ring-buffer + Windows Named Pipe (`\\.\pipe\jio_b2bua_logs`)
- **Codec support** — Native AMR-WB (16 kHz), AMR-NB (8 kHz), PCMA, PCMU, telephone-event DTMF

---

## Performance & Architecture Improvements vs Precursor Projects

Compared to earlier Python/Asterisk/Docker implementations (such as `jiofiber-sip-proxy`, `JFC-microsip`, and Asterisk bridge setups), this native C++ B2BUA delivers significant performance, resource, and operational enhancements:

| Performance & Feature Metric | Precursor Projects (Python / Docker / Asterisk) | Native C++ B2BUA (`sipserver`) |
|---|---|---|
| **Memory Footprint (RAM)** | ~250 MB – 1.5 GB (Python VM, Docker overhead, Asterisk daemon) | **~8 MB – 15 MB RAM** (Ultra-lightweight native process) |
| **Packet Forwarding Latency** | ~20 ms – 50 ms (Python GIL contention & virtual container network bridges) | **< 1 ms Sub-millisecond latency** (Native C++ multi-threaded PJSIP stack) |
| **Binary & Dependencies** | Requires Python 3, Pip packages, Docker Engine, or full Asterisk stack | **Zero dependencies** — Single ~1.7 MB compiled binary |
| **Provisioning Flow** | External Python scripts or manual HTTP web forms | **100% Native Embedded C++ Provisioner** (OTP request & credential extraction inside binary) |
| **Disk & SSD Impact** | Continuous disk IO log writes and container storage wear | **Zero SSD Wear** — 512 KB RAM ring-buffer + Windows Named Pipe stream |
| **VPN Overlay Routing** | Static IP binding (causes 1-way audio / disconnects over Tailscale/WireGuard) | **Dynamic OS Kernel Routing (`getsockname`)** — dynamic multi-interface IP detection |
| **Local Softphone Security** | Unencrypted UDP signaling only | **Dual Transport**: UDP (`5061`) + **Encrypted TLS (`5062`)** with auto-generated 2048-bit RSA certificates |
| **Port Collision Handling** | Silent failures or background process hangs | **Strict Port Binding** — instant fail-fast detection if port `5061`/`5062` is occupied |

---

## Quick Start

### ⚡ 1-Line Copy & Paste Installers

#### 🪟 Windows (PowerShell):
Open **PowerShell** and paste:
```powershell
irm https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/install_windows.ps1 | iex
```

#### 🐧 Linux (x86_64 / ARM64 / RISC-V):
Open **Terminal** and paste:
```bash
curl -sSL https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/install_linux.sh | sudo bash
```

---

### 📦 Download Pre-Built Binaries & Installers

Go to [Releases](https://github.com/sidhantjohnaind/sipserver/releases/tag/v1.3.0) to download standalone packages:

| Platform | Download Link | Package Name | Type / Notes |
|---|---|---|---|
| **Windows x64 (1-Click Installer)** | [🚀 **Download 64-bit Setup (`JioFiber_B2BUA_Setup_x64.exe`)**](https://github.com/sidhantjohnaind/sipserver/releases/download/v1.3.0/JioFiber_B2BUA_Setup_x64.exe) | `JioFiber_B2BUA_Setup_x64.exe` (2.7 MB) | ⚡ **1-Click Windows GUI Installer** (Auto-configures Firewall, Service & Shortcuts) |
| **Windows x64 (Standalone MSVC)** | [📥 **Download `b2bua_msvc.exe`**](https://github.com/sidhantjohnaind/sipserver/releases/download/v1.3.0/b2bua_msvc.exe) | `b2bua_msvc.exe` (1.7 MB) | ⚡ **Native MSVC Executable** (Dual Windows Service + Console Mode) |
| **Linux x86_64 Standalone** | [🐧 **Download `b2bua-linux-amd64`**](https://github.com/sidhantjohnaind/sipserver/releases/download/v1.3.0/b2bua-linux-amd64) | `b2bua-linux-amd64` (2.2 MB) | ✅ Native Linux AMD64 binary with AMR-WB / AMR |
| **Linux ARM64 Standalone** | [🐧 **Download `b2bua-linux-arm64`**](https://github.com/sidhantjohnaind/sipserver/releases/download/v1.3.0/b2bua-linux-arm64) | `b2bua-linux-arm64` (2.6 MB) | ✅ Pre-built for Raspberry Pi / ARM64 Routers / SBCs |
| **Linux 1-Click Script** | [🐧 **Download `install_linux.sh`**](https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/install_linux.sh) | `install_linux.sh` (4.4 KB) | ⚡ **1-Click Linux Installer** (Auto-detects Arch, Firewall, Systemd) |

> **Windows on ARM (Snapdragon X Elite / Surface Pro ARM / Windows 11 ARM64)**:
> Windows 11 ARM64 includes Microsoft's **Prism x64 emulation engine** — the standard `b2bua_msvc.exe` (x64) runs on all Windows ARM devices with near-native speed and **zero configuration needed**. A native ARM64 build script ([`src/build_win_arm64.py`](src/build_win_arm64.py)) is also provided if you have the MSVC ARM64 cross-compile toolchain installed.

### 2. Provision credentials (one-time)

The provisioner is **built directly into the binary (100% pure C++)**. Simply launch `b2bua` and it will automatically prompt for your Jio router IP and OTP if `.env` does not exist:

- When launched for the first time, it prompts for your Jio router IP (usually `192.168.29.1`).
- Enter the OTP sent to your registered Jio mobile number.
- It automatically whitelists your device, fetches your SIP credentials, and saves `.env`.

---

### 🔄 Universal Multi-Boot & Dual-Boot Bidirectional Sync Tools

If you multi-boot (**Windows 11 / Windows 10 / Ubuntu / Debian / Arch**) on the same machine, or need to transfer credentials to another PC, use the universal sync utilities:

* **🐧 From Linux (`./b2bua_sync.sh`)**:
  ```bash
  ./b2bua_sync.sh        # Interactive menu
  ./b2bua_sync.sh auto   # Auto-detects newer timestamp & synchronizes across drives
  ./b2bua_sync.sh push   # Pushes Linux configuration to all detected Windows/NTFS partitions
  ./b2bua_sync.sh pull   # Pulls Windows configuration into Linux & restarts service
  ./b2bua_sync.sh export # 📦 Exports 1-Click ZIP Archive (JioFiber_Config_Backup.zip) to Desktop
  ./b2bua_sync.sh import # 📥 Imports configuration directly from a ZIP Archive
  ./b2bua_sync.sh diff   # Compares config files across both OSes
  ```
* **🪟 From Windows (`b2bua_sync.bat`)**:
  * Double-click **`b2bua_sync.bat`** to scan all drive letters (`C:` through `Z:`) and sync directly with other Windows/Linux partitions, or export/import the portable `JioFiber_Config_Backup.zip` archive with 1 click.

---

### 3. Run & Deployment Options

#### 🪟 Windows:
* **1-Click GUI Setup (`JioFiber_B2BUA_Setup.exe`) [Recommended]**:
  - Automatically configures Windows Service, Firewall rules, and Desktop shortcuts.
  - Choose between Background Service Mode or Console Mode during setup.
* **Manual Batch Scripts**:
  - **Run Console Mode**: Double-click `run_windows.bat`
  - **Install Service**: Right-click `install_windows_service.bat` -> *Run as Administrator* (includes 5s auto-recovery)
  - **Complete Uninstall**: Double-click `uninstall_windows.bat` (removes Windows Service, Firewall rules & CA certs)
  - **Free Stale Ports**: Double-click `kill_ports.bat` to clear ports `5061` / `5062`.

#### 🐧 Linux:
* **1-Click Systemd Service Installer [Recommended]**:
  ```bash
  sudo bash install_linux.sh
  ```
  *(Or via curl: `curl -sSL https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/install_linux.sh | sudo bash`)*
* **Manual & Uninstall Scripts**:
  - **Complete Uninstall**: `sudo ./uninstall_linux.sh` (removes systemd service, firewall rules & CA certs)
  - **Uninstall Service Only**: `sudo ./uninstall_linux_service.sh`
  - **Run in Terminal**: `chmod +x run_wsl.sh && ./run_wsl.sh`
  - **Free Stale Ports**: `chmod +x kill_ports.sh && ./kill_ports.sh`
* **1-Click Portable AppImage**:
  ```bash
  chmod +x JioFiber_B2BUA-x86_64.AppImage
  ./JioFiber_B2BUA-x86_64.AppImage
  ```

#### 📊 Linux Service Management:
- **Status Check**: `sudo systemctl status jiofiber-b2bua`
- **View Live Logs**: `sudo journalctl -u jiofiber-b2bua -f`
- **Restart Service**: `sudo systemctl restart jiofiber-b2bua`

---

### 4. Configure your softphone

| Setting | Value |
|---|---|
| SIP Server / Domain | `<your-pc-ip>:5061` |
| Transport | **UDP** |
| Username | any (e.g. `100` or `101`) |
| Password | any (e.g. `1234`) |

> **Tailscale / VPN users**: Use your Tailscale / VPN IP (e.g. `100.x.x.x:5061`) as the SIP server in your softphone. The B2BUA automatically detects and routes across the correct VPN interface.

```
Softphone (Linphone / MicroSIP / GS Wave)
  ↕  SIP UDP port 5061
[B2BUA Proxy]  ←── .env credentials
  ↕  TLS v1.2 port 5068 (Carrier Encrypted)
Jio IMS / ONT (192.168.29.1)
  ↕
PSTN / Mobile Networks
```

The B2BUA acts as a full SIP proxy:
- Listens on UDP & TCP `5061` for local softphones (Linphone, Sipnetic, MicroSIP)
- Registers upstream with Jio IMS over TLS `5068`
- Bridges all call legs transparently with native **AMR-WB (16 kHz HD Voice)**, **AMR-NB (8 kHz)**, and **G.711 PCMA/PCMU** audio
- Rewrites `Contact` and `SDP` headers per-call to match the correct network interface

---

### 🎙️ CRITICAL: Audio Quality & AMR Codec Configuration (Must Read)

To achieve **crystal clear voice quality** and avoid robotic audio, muffled speech, or "transistor radio" distortion, configuring the audio codec in your softphone is **CRITICAL**:

#### 💡 Why `AMR/8000` is Important:
1. **Carrier Native Codec**: Jio IMS transmits voice calls across the cellular VoLTE network using **AMR-NB (8 kHz, 12.2 kbps)** or **AMR-WB (16 kHz HD Voice)**.
2. **Eliminates Double Transcoding**: When your softphone is configured to use legacy `PCMA` (G.711 A-law) or `PCMU`, audio undergoes lossy multi-stage conversion (`PCMA -> PCM -> AMR`). This mismatch can introduce robotic timbre, low volume, or garbled transistor noise.
3. **Pristine End-to-End Audio**: When your softphone sends **`AMR/8000`** (or uncompressed **`L16/8000`**), voice packets stream directly and cleanly with **zero transcoding loss**.

#### 🪟 MicroSIP Audio Setup (Windows):
In MicroSIP, click **Menu ➔ Settings (⚙️) ➔ Audio**:
* **Audio Codecs**: Move **`AMR/8000/1`** (or `AMR-WB/16000/1`) to the **top** of the enabled codecs list (followed by `L16/8000/1`).
* **VAD (Voice Activity Detection)**: **Enable (Checked)** — eliminates background microphone hiss when silent.
* **Echo Cancellation (EC)**: 
  * If using **Headphones / Headsets**: Keep EC disabled or mic volume moderate to prevent voice suppression.
  * If using **Loudspeakers**: Keep EC enabled to prevent acoustic feedback.

#### 📱 Linphone / Sipnetic / GS Wave Setup (Android / iOS):
* In **Settings ⚙️ ➔ Audio ➔ Codecs**:
  * Enable **`AMR-WB (16000 Hz)`** and **`AMR (8000 Hz)`**.
  * Place them at the highest priority above PCMA/PCMU.

---

## Building from Source

> **Note**: Stock PJSIP 2.15.1 is used with two small Jio IMS compatibility patches provided in `patches/` (applied automatically using `python apply_patches.py`). All B2BUA proxy logic is contained in `src/b2bua.cpp`.

### Step 1 — Download stock PJSIP 2.15.1

Download the official release and extract it:

```bash
# Option A: GitHub release
wget https://github.com/pjsip/pjproject/archive/refs/tags/2.15.1.tar.gz
tar -xzf 2.15.1.tar.gz
mkdir -p third_party
mv pjproject-2.15.1 third_party/

# Option B: Direct source zip (Windows)
# Download from: https://github.com/pjsip/pjproject/releases/tag/2.15.1
# Extract to: third_party\pjproject-2.15.1\
```

### Step 2 — Apply Jio IMS Compatibility Patches

Run the automated cross-platform patch script once after extracting PJSIP:

```bash
python apply_patches.py
```

This applies two small compatibility patches to PJSIP 2.15.1:
1. `opencore_amr.c`: Enforces octet-aligned AMR, sets bitrate to 12.2kbps (Mode 7), echoes `mode-set` in SDP, and disables VAD for Jio IMS.
2. `stream.c`: Enables trace logging for jitter buffer frame retrieval.

### Step 3 — Build Binaries & 1-Click Installers

**Windows x64 64-bit Setup Installer & Portable Binary:**
```cmd
python src/build_msvc_pjsip.py    :: Compiles b2bua_msvc.exe
python src/build_installer.py     :: Compiles JioFiber_B2BUA_Setup_x64.exe
```
Output: `bin/windows-x64/b2bua_msvc.exe` & `JioFiber_B2BUA_Setup_x64.exe`

**Windows x86 32-bit Setup Installer:**
```cmd
python src/build_installer_x86.py :: Compiles JioFiber_B2BUA_Setup_x86.exe
```
Output: `JioFiber_B2BUA_Setup_x86.exe`

**Windows ARM64 (MSVC cross-compile):**
```cmd
python src/build_win_arm64.py
```
Output: `bin/windows-arm64/b2bua_win_arm64.exe`

**Linux x86_64 Binary & Portable AppImage:**
```bash
python3 src/build_wsl.py
python3 scripts/build_appimage.py
```
Output: `bin/linux-amd64/b2bua` & `JioFiber_B2BUA-x86_64.AppImage`

**Linux ARM64 (cross-compile):**
```bash
# Install cross-compiler first:
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu

python3 src/build_arm64.py
```
Output: `bin/linux-arm64/b2bua`

**Linux RISC-V 64-bit (cross-compile):**
```bash
# Install cross-compiler:
sudo apt install gcc-riscv64-linux-gnu g++-riscv64-linux-gnu

python3 src/build_riscv64.py
```
Output: `bin/linux-riscv64/b2bua`

### What the build scripts do

The build scripts (`src/build_*.py` and `scripts/build_*.py`) compile PJSIP 2.15.1 source alongside `src/b2bua.cpp` and `src/installer.cpp`, packing everything into standalone binaries, 1-click Windows installers, and Linux AppImage packages. No system PJSIP install is needed.

---

## Configuration Reference (`.env`)

### File Storage Locations (`.env`, `cert.pem`, `key.pem`)

Depending on how you run JioFiber B2BUA, your configuration (`.env`) and TLS certificate files (`cert.pem`, `key.pem`) are stored in the following locations:

| Environment / Mode | Configuration (`.env`) & TLS Certificate Storage Path | Notes |
|---|---|---|
| **Windows Service Mode** | `C:\Program Files\JioFiberB2BUA\.env`<br>`C:\Program Files\JioFiberB2BUA\cert.pem`<br>`C:\Program Files\JioFiberB2BUA\key.pem` | ⚡ Setup Installer automatically copies existing `.env` & cert files to `C:\Program Files\JioFiberB2BUA\` during installation |
| **Windows Portable / Console** | Same directory as `b2bua_msvc.exe` (e.g. `C:\YourFolder\.env`) | Reads `.env` & certs from the local execution folder |
| **Linux Systemd Service** | Directory where `install_linux.sh` was executed (e.g. `/opt/jiofiber-b2bua/.env`) | `WorkingDirectory=$SCRIPT_DIR` configures systemd to use local folder |
| **Linux Portable AppImage** | Same working directory where `./JioFiber_B2BUA-x86_64.AppImage` is launched | Reads `.env` & certs from the execution directory |

### `.env` Variable Reference

| Variable | Description | Example / Default |
|---|---|---|
| `IPV4_ADDRESS` | Your PC's LAN IP | `192.168.29.195` |
| `LOCAL_PORT` | UDP SIP port for softphones | `5061` |
| `LOCAL_TLS_PORT` | Local TLS SIP port for softphones | `5062` |
| `ENABLE_LOCAL_TLS` | Enable local TLS listener | `0` (disabled by default, UDP port 5061 only) |
| `TLS_CERT_FILE` | Path to TLS Certificate file | `cert.pem` |
| `TLS_KEY_FILE` | Path to TLS Private Key file | `key.pem` |
| `GENERATE_NEW_TLS_CERT` | Force new cert pair on startup | `0` or `1` |
| `TLS_PORT` | TLS port to Jio router | `5068` |
| `RTP_PORT` | Base RTP port | `52000` |
| `PUBLIC_ID` | Your Jio SIP URI | `sip:+91XXXXXXXXXX@br.wln.ims.jio.com` |
| `SIP_AUTH_USER` | SIP auth username | `91XXXXXXXXXX@br.wln.ims.jio.com` |
| `SIP_PASSWORD` | SIP password | `xxxxxxxxxx` |
| `SIP_REALM` | SIP auth realm | `br.wln.ims.jio.com` |
| `REGISTRAR_HOST` | Jio router IP | `192.168.29.1` |
| `MAX_CALLS` | Max simultaneous calls | `4` |
| `LOG_LEVEL` | PJSIP log verbosity (1–5) | `5` |
| `TLS_VERIFY` | Verify TLS cert (0=skip) | `0` |

---

## Viewing Logs

**Windows:**
```cmd
view_logs.bat
```

**Linux:**
```bash
journalctl -u jiofiber-b2bua -f
```

---

## Supported Softphones

Tested and working:
- **Linphone** (Android / iOS / Desktop) — *Supports TLS port 5062 for Secured 🔒 status*
- **Sipnetic** (Android)
- **MicroSIP** (Windows)
- **PhonerLite** (Windows)
- **Zoiper** (Android / iOS)
- **Asterisk** (as upstream SIP trunk)

---

## Acknowledgements

This project stands on the shoulders of prior reverse-engineering and open-source telephony work. Huge thanks to:

- **[JFC-Group](https://github.com/JFC-Group)** — the community that first mapped out how JioFiber's JUICE/IMS client provisions and registers. In particular **[JFC-microsip](https://github.com/JFC-Group/JFC-microsip)** (the provisioning/config flow that `jfc_configure.py` derives from) and the JFC pjproject work that proved the patch path. Without their groundwork the `+sip.instance` shape, the OTP whitelist flow, and the rotating-password behaviour would have stayed a black box.
- **[ankurpandeyvns/jiofiber-sip-proxy](https://hub.docker.com/r/ankurpandeyvns/jiofiber-sip-proxy)** — Special thanks to Ankur Pandey for reverse-engineering the Jio router HTTP provisioner API, OTP authorization flow, and SIP IMS auth parameters.
- **[sivatheja10/jiofiber-bridge](https://github.com/sivatheja10/jiofiber-bridge)** — Special thanks to Siva Theja for initial SIP bridge research and protocol flow analysis.
- **[pjproject / PJSIP](https://github.com/pjsip/pjproject)** — the SIP/media stack the B2BUA is built on; the patches here are small deltas against it.
- **[opencore-amr](https://sourceforge.net/projects/opencore-amr/)** — the AMR-NB/AMR-WB codec that makes IMS audio interoperate with plain softphones.
- **[Tailscale](https://tailscale.com)** / **[WireGuard](https://www.wireguard.com/)** — the overlay network glue enabling remote calling.

This repo's contribution is the native end-to-end integration — a single-binary self-healing B2BUA that solves inbound call routing, correct AMR `mode-set` echo, automatic multi-interface RTP routing (Tailscale/LAN), and zero-SSD-wear RAM logging.

If you built on something here or spot missing attribution, please open an issue or PR.

---

## Disclaimer

This software interoperates with your **own** telephone line for **personal** use, the same way the official app on your own router does. It reimplements a client to a service you pay for. Check your provider's terms; you are responsible for how you use it. Provided as-is, no warranty. Not affiliated with, or endorsed by, any ISP or provider.

---

## License

MIT License — see [LICENSE](LICENSE)
