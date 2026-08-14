#!/usr/bin/env python3
"""
send_to_phone.py - 1-Click Mobile Web Server for Certificate Download & Setup
Zero external pip dependencies (Pure Python 3 standard library).

Serves a mobile-friendly download portal with 1-tap download buttons for
Android, iOS, and desktop softphones, plus an in-terminal QR code.
"""

import os
import sys
import socket
import urllib.parse
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT = 8000

def get_lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("1.1.1.1", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def find_certs_dir():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(script_dir, "certs"),
        os.path.join(os.path.expanduser("~"), "sipserver", "certs"),
        os.path.join(os.path.expanduser("~"), "Desktop", "JioFiber_TLS_Certs"),
        script_dir
    ]
    for c in candidates:
        if os.path.isdir(c) and any(f.endswith((".pem", ".crt", ".p12")) for f in os.listdir(c)):
            return c
    return script_dir

CERTS_DIR = find_certs_dir()

# Generate Simple ASCII QR Code for URL if qrcode package isn't installed
def print_qr(url):
    try:
        import qrcode
        qr = qrcode.QRCode(border=1)
        qr.add_data(url)
        qr.print_ascii(invert=True)
    except ImportError:
        # Fallback cleanly to text banner
        pass

HTML_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>JioFiber SIP — TLS Certificate Download</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
        body { background: #0f172a; color: #f8fafc; padding: 24px 16px; min-height: 100vh; display: flex; justify-content: center; }
        .container { max-width: 480px; width: 100%; }
        .header { text-align: center; margin-bottom: 24px; }
        .header h1 { font-size: 24px; color: #38bdf8; margin-bottom: 6px; }
        .header p { color: #94a3b8; font-size: 14px; }
        .card { background: #1e293b; border-radius: 16px; padding: 20px; margin-bottom: 16px; border: 1px solid #334155; }
        .card h2 { font-size: 18px; color: #e2e8f0; margin-bottom: 12px; display: flex; align-items: center; gap: 8px; }
        .btn { display: block; width: 100%; text-align: center; padding: 14px; border-radius: 10px; font-weight: 600; text-decoration: none; margin-top: 10px; transition: all 0.2s; font-size: 15px; }
        .btn-android { background: #22c55e; color: #0f172a; }
        .btn-ios { background: #38bdf8; color: #0f172a; }
        .btn-linphone { background: #f97316; color: #ffffff; }
        .btn:active { transform: scale(0.98); opacity: 0.9; }
        .steps { margin-top: 10px; font-size: 13px; color: #cbd5e1; line-height: 1.6; padding-left: 20px; }
        .badge { background: #334155; color: #38bdf8; padding: 2px 8px; border-radius: 6px; font-size: 12px; font-weight: bold; }
        .footer { text-align: center; color: #64748b; font-size: 12px; margin-top: 24px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔒 JioFiber SIP TLS Setup</h1>
            <p>1-Tap Certificate Download Portal for Softphones</p>
        </div>

        <!-- Samsung Galaxy / Android CA Certificate Section -->
        <div class="card" style="border-color: #3b82f6;">
            <h2>🌌 Samsung Galaxy / Android <span class="badge" style="color: #60a5fa; background: #1e3a8a;">cacert.crt</span></h2>
            <p style="font-size: 13px; color: #94a3b8;">Filtered for Samsung One UI & Android "Install CA Certificate" file picker.</p>
            <a href="/LocalLAN_RootCA.cacert.crt" class="btn" style="background: #3b82f6; color: #ffffff;">⬇️ Download LocalLAN_RootCA.cacert.crt</a>
            <ol class="steps">
                <li>Tap <b>Download</b> above.</li>
                <li>Go to phone <b>Settings ⚙️</b> ➔ <b>Security and privacy</b>.</li>
                <li>Tap <b>More security settings</b> ➔ <b>Install from device storage</b>.</li>
                <li>Select <b>CA certificate</b> ➔ Tap <b>Install anyway</b> ➔ Select downloaded <code>.cacert.crt</code> file.</li>
            </ol>
        </div>

        <!-- Android PKCS#12 Section -->
        <div class="card">
            <h2>📱 Android KeyStore <span class="badge">PKCS#12 (.p12)</span></h2>
            <p style="font-size: 13px; color: #94a3b8;">Standard Android VPN & App credentials bundle.</p>
            <a href="/LocalLAN_RootCA.p12" class="btn btn-android">⬇️ Download LocalLAN_RootCA.p12</a>
            <ol class="steps">
                <li>Tap <b>Download</b> above ➔ Enter password: <b><code>1234</code></b></li>
                <li>Set Credential Use to <b>VPN and Apps</b> / <b>CA Certificate</b>.</li>
            </ol>
        </div>

        <!-- iOS / iPhone Section -->
        <div class="card">
            <h2>🍏 iOS / iPhone <span class="badge">Profile (.pem)</span></h2>
            <p style="font-size: 13px; color: #94a3b8;">For iPhones and iPads (Safari & iOS SIP clients).</p>
            <a href="/LocalLAN_RootCA.pem" class="btn btn-ios">⬇️ Download LocalLAN_RootCA.pem</a>
            <ol class="steps">
                <li>Tap <b>Download</b> above ➔ Allow profile download.</li>
                <li>Go to <b>Settings ⚙️</b> ➔ Tap <b>Profile Downloaded</b> ➔ Install.</li>
                <li>Go to <b>Settings</b> ➔ <b>General</b> ➔ <b>About</b> ➔ <b>Certificate Trust Settings</b> ➔ Enable <b>Full Trust</b>.</li>
            </ol>
        </div>

        <!-- Linphone App Direct -->
        <div class="card">
            <h2>📞 Linphone Softphone <span class="badge">Direct Root CA (.crt)</span></h2>
            <p style="font-size: 13px; color: #94a3b8;">Directly import into Linphone (no OS trust required).</p>
            <a href="/LocalLAN_RootCA.crt" class="btn btn-linphone">⬇️ Download LocalLAN_RootCA.crt</a>
            <ol class="steps">
                <li>Download the certificate to your phone.</li>
                <li>In <b>Linphone</b> ➔ <b>Settings ⚙️</b> ➔ <b>Network</b> ➔ <b>Root CA Certificate</b> ➔ Select downloaded file.</li>
                <li>Set Transport to <b>TLS</b> and port to <b>5062</b>.</li>
            </ol>
        </div>

        <div class="footer">
            Server IP: <b>{LAN_IP}</b> | Port: 5062 (TLS) / 5061 (UDP)
        </div>
    </div>
</body>
</html>
"""

class CertRequestHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=CERTS_DIR, **kwargs)

    def guess_type(self, path):
        if path.endswith((".crt", ".cacert.crt")):
            return "application/x-x509-ca-cert"
        if path.endswith((".pem", ".cacert.pem")):
            return "application/x-pem-file"
        if path.endswith((".p12", ".pfx")):
            return "application/x-pkcs12"
        return super().guess_type(path)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path in ("/", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            body = HTML_PAGE.replace("{LAN_IP}", get_lan_ip()).encode("utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        
        # Fallback aliases
        alias_map = {
            "/LocalLAN_RootCA.cacert.crt": "LocalLAN_RootCA.crt",
            "/LocalLAN_RootCA.cacert.pem": "LocalLAN_RootCA.pem",
            "/cacert.crt": "LocalLAN_RootCA.crt",
            "/cacert.pem": "LocalLAN_RootCA.pem",
            "/cert.p12": "LocalLAN_RootCA.p12",
            "/cert.pfx": "LocalLAN_RootCA.pfx",
            "/cert.pem": "LocalLAN_RootCA.pem",
            "/cert.crt": "LocalLAN_RootCA.crt",
            "/key.pem":  "LocalLAN_RootCA.key",
            "/JioFiberB2BUA.pem": "LocalLAN_RootCA.pem",
            "/JioFiberB2BUA.p12": "LocalLAN_RootCA.p12",
            "/JioFiberB2BUA.crt": "LocalLAN_RootCA.crt",
        }
        
        req_path = parsed.path
        if req_path in alias_map:
            alias_target = os.path.join(CERTS_DIR, alias_map[req_path])
            if os.path.exists(alias_target):
                self.path = "/" + alias_map[req_path]

        return super().do_GET()

class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True

def run_server():
    lan_ip = get_lan_ip()
    port = PORT
    server = None
    
    for candidate_port in (8000, 8080, 8888, 5000, 9000):
        try:
            server = ReusableHTTPServer(("0.0.0.0", candidate_port), CertRequestHandler)
            port = candidate_port
            break
        except OSError:
            continue
            
    if not server:
        print("[ERROR] Could not bind to any port (8000, 8080, 8888, 5000).")
        sys.exit(1)

    url = f"http://{lan_ip}:{port}/"
    
    print("=" * 65)
    print("   📱 JioFiber SIP & TLS — Mobile Certificate Delivery Server")
    print("=" * 65)
    print(f"\n[*] Open this URL in your phone browser:")
    print(f"    👉  \033[1;32m{url}\033[0m\n")
    print(f"[*] Serving certificates from: {CERTS_DIR}\n")
    
    print_qr(url)
    
    print("[*] Press Ctrl+C to stop the server anytime.")
    print("=" * 65)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Server stopped.")
        server.server_close()

if __name__ == "__main__":
    run_server()
