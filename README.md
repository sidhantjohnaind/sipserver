# JioFiber SIP B2BUA

A lightweight, native **SIP Back-to-Back User Agent (B2BUA)** that bridges JioFiber VoIP (Jio IMS) to any standard SIP softphone — over LAN, Tailscale, ZeroTier, WireGuard, or any VPN.

No Docker. No Asterisk. No cloud. Runs as a single binary.

---

## Features

- **Zero-dependency binary** — single executable for Windows, Linux x86_64, and Linux ARM64
- **Embedded Native OTP Provisioner** — automatically requests OTP and provisions credentials directly from your Jio router without needing Python
- **Dual Transport Support (UDP & TLS)**:
  - Local Listener: Standard UDP (`5061`) + Encrypted TLS (`5062` / `LOCAL_TLS_PORT`) for softphones
  - Upstream Transport: TLS v1.2 (`5068`) to Jio IMS router/ONT
- **Local TLS Auto Certificate Generator**: Automatically creates 10-year 2048-bit RSA self-signed `cert.pem` and `key.pem` files on disk for encrypted softphone signaling
- **Strict Port Binding**: Binds directly to `5061` and `5062` and exits immediately if either port is in use
- **Automatic SIP registration** with Jio IMS over TLS with self-healing credential rotation recovery
- **Full call flow bridging** — outgoing calls, incoming calls, BYE, CANCEL, re-INVITE
- **Multi-network support** — LAN, Tailscale, ZeroTier, WireGuard, OpenVPN
  - Per-call dynamic source IP detection using OS kernel routing table (`getsockname` connect trick)
  - Solves one-way audio and call teardown failures across VPN overlays
  - Zero static IP configuration needed
- **Robust Teardown Handling** — clean SIP `CANCEL` & `BYE` handling without double-hangup assertions
- **PUBLISH / presence** passthrough for softphone status
- **Zero SSD wear logging** — 512 KB RAM ring-buffer + Windows Named Pipe (`\\.\pipe\jio_b2bua_logs`)
- **Codec support** — AMR-NB (octet-aligned mode-set), PCMA, PCMU, telephone-event DTMF

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

### 1. Download a pre-built binary / 1-Click Installer

Go to [Releases](https://github.com/sidhantjohnaind/sipserver/releases/tag/v1.0.0) and download the 1-click installer or standalone binary for your target platform:

| Platform | Download Link | Package Name | Type / Notes |
|---|---|---|---|
| **Windows x64 64-bit (1-Click Installer)** | [🚀 **Download 64-bit Setup (`JioFiber_B2BUA_Setup_x64.exe`)**](https://github.com/sidhantjohnaind/sipserver/releases/download/v1.0.0/JioFiber_B2BUA_Setup_x64.exe) | `JioFiber_B2BUA_Setup_x64.exe` (228 KB) | ⚡ **1-Click 64-bit Windows Installer** (Auto-configures Firewall, Service & Shortcuts) |
| **Windows x86 32-bit (1-Click Installer)** | [🚀 **Download 32-bit Setup (`JioFiber_B2BUA_Setup_x86.exe`)**](https://github.com/sidhantjohnaind/sipserver/releases/download/v1.0.0/JioFiber_B2BUA_Setup_x86.exe) | `JioFiber_B2BUA_Setup_x86.exe` (188 KB) | ⚡ **1-Click 32-bit Windows Installer** (Compatible with legacy 32-bit Windows systems) |
| **Windows Portable** | [📥 Download `b2bua_msvc.exe`](https://github.com/sidhantjohnaind/sipserver/releases/download/v1.0.0/b2bua_msvc.exe) | `b2bua_msvc.exe` (1.7 MB) | ✅ Zero-dependency standalone MSVC binary |
| **Linux 1-Click Script (x86_64 / ARM64)** | [🐧 **Download `install_linux.sh`**](https://github.com/sidhantjohnaind/sipserver/releases/download/v1.0.0/install_linux.sh) | `install_linux.sh` (2.5 KB) | ⚡ **1-Click Linux Installer** (Auto-detects Arch, Firewall, Service) |
| **Linux x86_64 (AppImage)** | [🐧 **Download `JioFiber_B2BUA-x86_64.AppImage`**](https://github.com/sidhantjohnaind/sipserver/releases/download/v1.0.0/JioFiber_B2BUA-x86_64.AppImage) | `JioFiber_B2BUA-x86_64.AppImage` (835 KB) | ⚡ **1-Click Portable Linux AppImage** |
| **Linux x86_64 Standalone** | [📥 Download `b2bua-linux-amd64`](https://github.com/sidhantjohnaind/sipserver/releases/download/v1.0.0/b2bua-linux-amd64) | `b2bua-linux-amd64` (1.9 MB) | ✅ Pre-built Linux binary |
| **Linux ARM64** | [📥 Download `b2bua-linux-arm64`](https://github.com/sidhantjohnaind/sipserver/releases/download/v1.0.0/b2bua-linux-arm64) | `b2bua-linux-arm64` (1.8 MB) | ✅ Pre-built for Raspberry Pi / Routers |
| **Linux RISC-V 64** | `b2bua` (linux-riscv64) | `b2bua` | 🔧 Build from source via `python src/build_riscv64.py` |

> **Windows on ARM (Snapdragon X Elite / Surface Pro ARM / Windows 11 ARM64)**:
> Windows 11 ARM64 includes Microsoft's **Prism x64 emulation engine** — the standard `b2bua_msvc.exe` (x64) runs on all Windows ARM devices with near-native speed and **zero configuration needed**. A native ARM64 build script ([`src/build_win_arm64.py`](src/build_win_arm64.py)) is also provided if you have the MSVC ARM64 cross-compile toolchain installed.

### 2. Provision credentials (one-time)

The provisioner is **built directly into the binary (100% pure C++)**. Simply launch `b2bua` and it will automatically prompt for your Jio router IP and OTP if `.env` does not exist:

- When launched for the first time, it prompts for your Jio router IP (usually `192.168.29.1`).
- Enter the OTP sent to your registered Jio mobile number.
- Prompt for Local TLS Certificate Setup:
  - **Option 1 [Default]**: Generate a brand new TLS certificate pair (`cert.pem` & `key.pem`).
  - **Option 2**: Keep & use existing `cert.pem` from disk.
  - **Option 3**: Disable Local TLS (UDP port 5061 only mode).
- It automatically whitelists your device, fetches your SIP credentials, and saves `.env`.

---

### How to Generate & Install TLS Certificates for Softphones (Linphone / Zoiper)

When Local TLS is enabled on port `5062`, `b2bua` provides high-compatibility X.509 v3 certificates with Subject Alternative Names (SAN) matching your local LAN host IP (e.g. `192.168.29.x`):

#### 🛠️ 1-Click Native Certificate Generator (Zero Python):
* **Linux**: Run `./generate_certs.sh` (or `./generate_certs.sh 192.168.29.x`)
* **Windows**: Double-click `generate_certs.bat`
* **Open Folder**: Run `./open_tls_cert.sh` on Linux or double-click `open_tls_cert.bat` on Windows to open the `certs/` directory directly.

#### 📂 Generated Certificate Files (inside `certs/` & Desktop):
1. **`cert.pem` / `cert.crt`**: Standard X.509 v3 public certificate with LAN IP SANs & `CA:TRUE`.
2. **`cert.p12` / `cert.pfx`**: Android/iOS Universal PKCS#12 bundle (Password: **`1234`**).
3. **`key.pem`**: 2048-bit server private key.

#### 📱 How to Transfer & Install on Phone / Softphones:

* **Transfer Method (Optional Python Local Web Server)**:
  ```bash
  python -m http.server 8000
  ```
  Open phone browser to `http://<your-pc-ip>:8000/certs/cert.pem` (or use USB cable, AirDrop, Google Drive, Email).

* **Inside Linphone App (Easiest — 0 OS install needed)**:
  1. Transfer `cert.pem` to your phone.
  2. In **Linphone** -> **Settings ⚙️** -> **Network** -> **Root CA Certificate** -> Select `cert.pem`.
  3. Set Transport to **TLS** (Port `5062`).

* **Android System KeyStore ("VPN & App User Certificate")**:
  1. Transfer `cert.p12` to your phone.
  2. Tap `cert.p12` -> Enter password: **`1234`** -> Tap **OK**. (Uses 3DES compatibility encryption).

* **🍏 iOS / iPhone**:
  1. Download `cert.pem` into the **Files app** on your iPhone.
  2. Open iPhone **Settings** -> Tap **Profile Downloaded** -> Tap **Install**.
  3. Go to **Settings** -> **General** -> **About** -> **Certificate Trust Settings** -> Enable **Full Trust** for `JioFiberB2BUA`.

* **💻 Windows / Desktop**:
  * **MicroSIP**: In Settings -> Network -> Check **TLS** and select `cert.pem` as CA file.
  * **Linphone Desktop**: Preferences -> Network -> Advanced -> Select `cert.pem` as Root CA.

---

### 3. Run & Deployment Options

#### 🪟 Windows:
* **1-Click GUI Setup (`JioFiber_B2BUA_Setup.exe`) [Recommended]**:
  - Automatically configures Windows Service, Firewall rules, and Desktop shortcuts.
  - Choose between Background Service Mode or Console Mode during setup.
* **Manual Batch Scripts**:
  - **Run Console Mode**: Double-click `run_windows.bat`
  - **Install Service**: Right-click `install_windows_service.bat` -> *Run as Administrator* (includes 5s auto-recovery)
  - **Uninstall Service**: Right-click `uninstall_windows_service.bat` -> *Run as Administrator*
  - **Free Stale Ports**: Double-click `kill_ports.bat` to clear ports `5061` / `5062`.

#### 🐧 Linux:
* **1-Click Systemd Service Installer [Recommended]**:
  ```bash
  sudo bash install_linux.sh
  ```
  *(Or via curl: `curl -sSL https://raw.githubusercontent.com/sidhantjohnaind/sipserver/master/install_linux.sh | sudo bash`)*
* **Manual Service Scripts**:
  - **Install Service**: `sudo ./install_linux_service.sh`
  - **Uninstall Service**: `sudo ./uninstall_linux_service.sh`
  - **Run in WSL / Terminal**: `chmod +x run_wsl.sh && ./run_wsl.sh`
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
| SIP Server / Domain | `<your-pc-ip>:5061` (UDP) or `<your-pc-ip>:5062` (TLS) |
| Transport | UDP or TLS |
| Username | any (e.g. `101`) |
| Password | any |

> **TLS / Linphone Note**: When using **TLS** transport on port `5062`, Linphone displays **Secured 🔒** once `cert.pem` is imported into Linphone or your phone's Trust Store.
>
> **Tailscale users**: Use your Tailscale IP (e.g. `100.x.x.x:5061` or `100.x.x.x:5062`) as the SIP server in your softphone. The B2BUA automatically detects and uses the correct Tailscale interface.

```
Softphone (SIP/UDP or SIP/TLS)
  ↕  UDP port 5061 / TLS port 5062
[B2BUA]  ←── .env credentials
  ↕  TLS port 5068
Jio IMS / ONT (192.168.29.1)
  ↕
PSTN / Phone Numbers
```

The B2BUA acts as a full SIP proxy:
- Listens on UDP `5061` and TLS `5062` for local softphones
- Registers upstream with Jio IMS over TLS `5068`
- Bridges all call legs transparently
- Rewrites `Contact` and `SDP` headers per-call to match the correct network interface

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
| `ENABLE_LOCAL_TLS` | Enable local TLS listener | `1` (or `0` to disable) |
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
