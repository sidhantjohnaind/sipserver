#!/usr/bin/env python3
"""
sip_proxy.py - Pure Python JioFiber SIP B2BUA Proxy
Handles softphone REGISTER requests with 200 OK and bridges calls to Jio Fiber IMS.

Usage:
    python scripts/sip_proxy.py
"""

import os
import sys
import socket
import ssl
import select
import threading

def load_env(env_path=".env"):
    if not os.path.exists(env_path):
        env_path = "../.env"
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    os.environ[k.strip()] = v.strip('"\' ')

class SIPProxy:
    def __init__(self, local_port=5061, upstream_host="192.168.29.1", upstream_port=5068):
        self.local_port = local_port
        self.upstream_host = upstream_host
        self.upstream_port = upstream_port
        self.udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.running = True

    def start(self):
        try:
            self.udp_sock.bind(("0.0.0.0", self.local_port))
            print(f"=====================================================================")
            print(f" [Python B2BUA Proxy] Listening on UDP 0.0.0.0:{self.local_port}")
            print(f" [Python B2BUA Proxy] Upstream Target: TLS {self.upstream_host}:{self.upstream_port}")
            print(f"=====================================================================\n")
        except Exception as e:
            print(f"[!] Bind error on port {self.local_port}: {e}")
            sys.exit(1)

        while self.running:
            try:
                data, addr = self.udp_sock.recvfrom(65535)
                if not data:
                    continue
                threading.Thread(target=self.handle_packet, args=(data, addr), daemon=True).start()
            except KeyboardInterrupt:
                print("\n[*] Stopping Python B2BUA Proxy...")
                break
            except Exception as e:
                continue

    def handle_packet(self, data, addr):
        try:
            text = data.decode('utf-8', errors='ignore')
            lines = text.splitlines()
            if not lines:
                return
            
            first_line = lines[0]

            # 1. Handle softphone REGISTER requests with 200 OK
            if first_line.startswith("REGISTER"):
                print(f"[*] [REGISTER] Softphone {addr[0]}:{addr[1]} -> Responding 200 OK")
                resp = self.build_200_ok(lines, text)
                self.udp_sock.sendto(resp.encode('utf-8'), addr)

            # 2. Handle softphone INVITE call requests
            elif first_line.startswith("INVITE"):
                print(f"[*] [INVITE] Call from {addr[0]}:{addr[1]} -> Bridging to Jio IMS TLS...")
                self.udp_sock.sendto(b"SIP/2.0 180 Ringing\r\n\r\n", addr)
                # Forward over TLS socket to Jio IMS
                self.forward_tls(data, addr)

            elif first_line.startswith("CANCEL") or first_line.startswith("BYE"):
                self.udp_sock.sendto(b"SIP/2.0 200 OK\r\n\r\n", addr)

        except Exception as e:
            print(f"[!] Error processing packet: {e}")

    def build_200_ok(self, lines, text):
        via = [l for l in lines if l.lower().startswith("via:")]
        from_hdr = [l for l in lines if l.lower().startswith("from:")]
        to_hdr = [l for l in lines if l.lower().startswith("to:")]
        call_id = [l for l in lines if l.lower().startswith("call-id:")]
        cseq = [l for l in lines if l.lower().startswith("cseq:")]
        contact = [l for l in lines if l.lower().startswith("contact:")]

        resp_lines = ["SIP/2.0 200 OK"]
        if via: resp_lines.append(via[0])
        if from_hdr: resp_lines.append(from_hdr[0])
        if to_hdr: resp_lines.append(to_hdr[0] + (";tag=pythonb2bua" if "tag=" not in to_hdr[0] else ""))
        if call_id: resp_lines.append(call_id[0])
        if cseq: resp_lines.append(cseq[0])
        if contact: resp_lines.append(contact[0])
        resp_lines.extend(["Expires: 3600", "Content-Length: 0", "", ""])
        return "\r\n".join(resp_lines)

    def forward_tls(self, data, client_addr):
        try:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE

            with socket.create_connection((self.upstream_host, self.upstream_port), timeout=5) as s:
                with ctx.wrap_socket(s, server_hostname=self.upstream_host) as tls:
                    tls.sendall(data)
                    resp = tls.recv(4096)
                    if resp:
                        self.udp_sock.sendto(resp, client_addr)
        except Exception as e:
            print(f"[!] TLS Forward error to Jio IMS: {e}")

if __name__ == "__main__":
    load_env()
    port = int(os.getenv("LOCAL_PORT", "5061"))
    proxy = SIPProxy(local_port=port)
    proxy.start()
