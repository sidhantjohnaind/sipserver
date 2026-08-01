# JioFiber SIP B2BUA

A lightweight, native **SIP Back-to-Back User Agent (B2BUA)** that bridges JioFiber VoIP (Jio IMS) to any standard SIP softphone — over LAN, Tailscale, ZeroTier, WireGuard, or any VPN.

No Docker. No Asterisk. No cloud. Runs as a single binary.

---

## Features

- **Zero-dependency binary** — single executable for Windows, Linux x86_64, and Linux ARM64
- **Embedded Native OTP Provisioner** — automatically requests OTP and provisions credentials directly from your Jio router without needing Python
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

## Quick Start

### 1. Download a pre-built binary

Go to [Releases](../../releases) and download the binary for your platform:

| Platform | File |
|---|---|
| Windows x64 | `b2bua_msvc.exe` |
| Linux x86_64 | `b2bua` (linux-amd64) |
| Linux ARM64 | `b2bua` (linux-arm64) |

### 2. Provision credentials (one-time)

The provisioner is **built directly into the binary**. Simply launch `b2bua` and it will automatically prompt for your Jio router IP and OTP if `.env` does not exist:

- When launched for the first time, it prompts for your Jio router IP (usually `192.168.29.1`).
- Enter the OTP sent to your registered Jio mobile number.
- It automatically whitelists your device, fetches your SIP credentials, and saves `.env`.

> **Optional**: If you prefer to provision manually via Python before running the binary, you can run:
> ```bash
> python create_env_jfibersip.py
> ```
> Or copy `.env.example` to `.env` and fill in manually.

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

### Step 3 — Build

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

The build scripts (`src/build_*.py`) compile PJSIP 2.15.1 source alongside our single `src/b2bua.cpp` file and link everything into a single standalone executable. No system PJSIP install is needed.

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
