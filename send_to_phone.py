#!/usr/bin/env python3
"""
send_to_phone.py - 1-Click Mobile Web Server for Fast Softphone Setup
Zero external pip dependencies (Pure Python 3 standard library).

Serves a mobile-friendly setup portal for Android (Samsung One UI), iOS, and PC softphones.
"""

import os
import sys
import socket
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

def print_qr(url):
    try:
        import qrcode
        qr = qrcode.QRCode(border=1)
        qr.add_data(url)
        qr.print_ascii(invert=True)
    except ImportError:
        pass

HTML_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>JioFiber SIP — Mobile Setup</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
        body { background: #0f172a; color: #f8fafc; padding: 24px 16px; min-height: 100vh; display: flex; justify-content: center; }
        .container { max-width: 480px; width: 100%; }
        .header { text-align: center; margin-bottom: 24px; }
        .header h1 { font-size: 24px; color: #38bdf8; margin-bottom: 6px; }
        .header p { color: #94a3b8; font-size: 14px; }
        .card { background: #1e293b; border-radius: 16px; padding: 20px; margin-bottom: 16px; border: 1px solid #334155; }
        .card h2 { font-size: 18px; color: #e2e8f0; margin-bottom: 12px; display: flex; align-items: center; gap: 8px; }
        .info-box { background: #0f172a; padding: 12px; border-radius: 8px; border: 1px solid #334155; margin-bottom: 12px; }
        .info-row { display: flex; justify-content: space-between; margin-bottom: 6px; font-size: 14px; }
        .info-row:last-child { margin-bottom: 0; }
        .info-label { color: #94a3b8; }
        .info-val { font-weight: bold; color: #38bdf8; font-family: monospace; }
        .btn { display: block; width: 100%; text-align: center; padding: 14px; border-radius: 10px; font-weight: 600; text-decoration: none; margin-top: 10px; transition: all 0.2s; font-size: 15px; }
        .btn-linphone { background: #f97316; color: #ffffff; }
        .btn-sipnetic { background: #22c55e; color: #0f172a; }
        .steps { margin-top: 10px; font-size: 13px; color: #cbd5e1; line-height: 1.6; padding-left: 20px; }
        .footer { text-align: center; color: #64748b; font-size: 12px; margin-top: 24px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📞 JioFiber SIP Mobile Setup</h1>
            <p>High-Definition VoLTE Calling via B2BUA</p>
        </div>

        <div class="card" style="border-color: #38bdf8;">
            <h2>⚙️ Softphone Connection Info</h2>
            <div class="info-box">
                <div class="info-row">
                    <span class="info-label">SIP Domain / Proxy:</span>
                    <span class="info-val">SERVER_IP:5061</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Transport:</span>
                    <span class="info-val">UDP</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Username:</span>
                    <span class="info-val">100 (or 101)</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Password:</span>
                    <span class="info-val">1234</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Audio Codecs:</span>
                    <span class="info-val">AMR-WB (16kHz), PCMA</span>
                </div>
            </div>
        </div>

        <div class="card">
            <h2>📱 Linphone Setup (Recommended)</h2>
            <p style="font-size: 13px; color: #94a3b8;">Zero-configuration setup for Samsung Galaxy & Android.</p>
            <a href="https://play.google.com/store/apps/details?id=org.linphone" target="_blank" class="btn btn-linphone">📲 Open Linphone in Play Store</a>
            <ol class="steps">
                <li>Open <b>Linphone</b> ➔ Tap <b>Use SIP Account</b>.</li>
                <li>Enter Domain: <code>SERVER_IP:5061</code>.</li>
                <li>Set Transport to <b>UDP</b>.</li>
                <li>Tap <b>Log In</b> ➔ Status turns <b>🟢 Connected</b>.</li>
            </ol>
        </div>

        <div class="footer">
            JioFiber SIP B2BUA &bull; HD Voice VoLTE Bridge
        </div>
    </div>
</body>
</html>
"""

class SetupHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        lan_ip = get_lan_ip()
        page = HTML_PAGE.replace("SERVER_IP", lan_ip)
        self.send_response(200)
        self.send_header("Content-type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page.encode("utf-8"))))
        self.end_headers()
        self.wfile.write(page.encode("utf-8"))

def main():
    lan_ip = get_lan_ip()
    url = f"http://{lan_ip}:{PORT}"
    
    print("\n" + "=" * 60)
    print("   JioFiber SIP — Mobile Setup Portal")
    print("=" * 60)
    print(f"\n[+] Mobile Setup URL : {url}")
    print(f"[+] SIP Server Port  : {lan_ip}:5061 (UDP)\n")
    print("Scan this QR code with your phone camera:")
    print_qr(url)
    print("=" * 60)
    print(f"[*] Serving setup portal on port {PORT}... (Press Ctrl+C to stop)\n")

    httpd = HTTPServer(("0.0.0.0", PORT), SetupHandler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[!] Server stopped.")

if __name__ == "__main__":
    main()
