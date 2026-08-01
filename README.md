# JioFiber SIP B2BUA

A lightweight, native **SIP Back-to-Back User Agent (B2BUA)** that bridges JioFiber VoIP (Jio IMS) to any standard SIP softphone — over LAN, Tailscale, ZeroTier, WireGuard, or any VPN.

No Docker. No Asterisk. No cloud. Runs as a single binary.

---

## Features

- **Zero-dependency binary** — single executable for Windows, Linux x86_64, and Linux ARM64
- **Automatic SIP registration** with Jio IMS over TLS
- **Full call bridging** — outgoing calls, incoming calls, BYE, CANCEL, re-INVITE
- **Multi-network support** — LAN, Tailscale, ZeroTier, WireGuard, OpenVPN
  - Automatically detects the correct local IP per-call using OS routing table
  - No static IP configuration needed
- **PUBLISH / presence** passthrough for softphone status
- **Zero SSD wear logging** — 512 KB RAM ring-buffer + Windows Named Pipe (`\\.\pipe\jio_b2bua_logs`)
- **Codec support** — AMR-NB, PCMA, PCMU, telephone-event DTMF

---

## Quick Start

### 1. Download a pre-built binary

Go to [Releases](../../releases) and download the binary for your platform:

| Platform | File |
|---|---|
| Windows x64 | `b2bua_msvc.exe` |
| Linux x86_64 | `b2bua` (linux-amd64) |
| Linux ARM64 | `b2bua` (linux-arm64) |

### 2. Provision credentials (one-time)

Run the Python provisioner to extract your SIP credentials from the Jio router automatically:

```bash
python create_env_jfibersip.py
```

- Enter your Jio router IP (usually `192.168.29.1`)
- Enter the OTP sent to your Jio registered mobile number
- A `.env` file is created automatically with all credentials

Or copy `.env.example` to `.env` and fill in manually.

### 3. Run

**Windows:**
```cmd
run_windows.bat
```

**Linux / WSL:**
```bash
chmod +x run_wsl.sh
./run_wsl.sh
```

**Linux (native, as service):**
```bash
chmod +x install_linux_service.sh
sudo ./install_linux_service.sh
```

### 4. Configure your softphone

| Setting | Value |
|---|---|
| SIP Server / Domain | `<your-pc-ip>:5061` |
| Transport | UDP |
| Username | any (e.g. `101`) |
| Password | any |

> **Tailscale users**: Use your Tailscale IP (e.g. `100.x.x.x:5061`) as the SIP server in your softphone. The B2BUA automatically detects and uses the correct Tailscale interface.

---

## Architecture

```
Softphone (SIP/UDP)
  ↕  port 5061
[B2BUA]  ←── .env credentials
  ↕  TLS port 5068
Jio IMS / ONT (192.168.29.1)
  ↕
PSTN / Phone Numbers
```

The B2BUA acts as a full SIP proxy:
- Listens on UDP `5061` for local softphones
- Registers upstream with Jio IMS over TLS `5068`
- Bridges all call legs transparently
- Rewrites `Contact` and `SDP` headers per-call to match the correct network interface

---

## Building from Source

> **Note**: We do **not** modify any PJSIP source files. All B2BUA logic is in `src/b2bua.cpp` only, which uses the standard PJSIP public API. You can use a completely stock, unmodified PJSIP download.

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

### Step 2 — Build

**Windows (MSVC — no MinGW/WSL needed):**
```cmd
python src/build_msvc_pjsip.py
```
Output: `bin/windows-x64/b2bua_msvc.exe`

**Linux x86_64:**
```bash
python3 src/build_wsl.py
cp b2bua_wsl bin/linux-amd64/b2bua
```

**Linux ARM64 (cross-compile):**
```bash
# Install cross-compiler first:
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu

python3 src/build_arm64.py
```
Output: `bin/linux-arm64/b2bua`

### What the build scripts do

The build scripts (`src/build_*.py`) compile **unmodified PJSIP 2.15.1** source alongside our single `src/b2bua.cpp` file and link everything into a single standalone executable. No system PJSIP install is needed.

---

## Configuration Reference (`.env`)

| Variable | Description | Example |
|---|---|---|
| `IPV4_ADDRESS` | Your PC's LAN IP | `192.168.29.195` |
| `LOCAL_PORT` | UDP SIP port for softphones | `5061` |
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
- **Linphone** (Android / iOS / Desktop)
- **Sipnetic** (Android)
- **MicroSIP** (Windows)
- **PhonerLite** (Windows)
- **Zoiper** (Android / iOS)
- **Asterisk** (as upstream SIP trunk)

---

## Credits & Acknowledgments

This project builds upon the foundational research and contributions of the open-source VoIP community:

- **[Teluu / PJSIP Team](https://www.pjsip.org/)** — For the open-source SIP protocol stack and PJSUA2 C/C++ libraries.
- **Martin Storsjö** — For the `opencore-amr` wrapper libraries enabling AMR-NB and AMR-WB audio codec support.
- **JioFiber VoIP Community & Early Contributors** — Special thanks to earlier developers who reverse-engineered the Jio Router TR-069 / HTTP provisioner API and SIP digest auth parameters (OTP flow, user-agent whitelisting, and IMS realm structure).

---

## License

MIT License — see [LICENSE](LICENSE)
