#!/usr/bin/env python3
"""
sip_sniffer.py - Linux Raw Socket Network Traffic Sniffer
Captures and displays all unencrypted SIP, HTTP, and network traffic in cleartext.

Usage on Linux:
    sudo python3 sip_sniffer.py [interface]
Example:
    sudo python3 sip_sniffer.py eth0
    sudo python3 sip_sniffer.py any
"""

import socket
import struct
import sys
import datetime

def parse_ethernet_header(raw_data):
    dest_mac, src_mac, proto = struct.unpack('! 6s 6s H', raw_data[:14])
    dest_mac_str = ':'.join(f'{b:02x}' for b in dest_mac)
    src_mac_str = ':'.join(f'{b:02x}' for b in src_mac)
    return dest_mac_str, src_mac_str, socket.htons(proto), raw_data[14:]

def parse_ip_header(raw_data):
    version_header_len = raw_data[0]
    version = version_header_len >> 4
    header_len = (version_header_len & 15) * 4
    ttl, proto, src, target = struct.unpack('! 8x B B 2x 4s 4s', raw_data[:20])
    src_ip = socket.inet_ntoa(src)
    dest_ip = socket.inet_ntoa(target)
    return version, header_len, ttl, proto, src_ip, dest_ip, raw_data[header_len:]

def parse_tcp_header(raw_data):
    src_port, dest_port, sequence, acknowledgment, offset_reserved_flags = struct.unpack('! H H L L H', raw_data[:14])
    offset = (offset_reserved_flags >> 12) * 4
    return src_port, dest_port, sequence, acknowledgment, offset, raw_data[offset:]

def parse_udp_header(raw_data):
    src_port, dest_port, length = struct.unpack('! H H H 2x', raw_data[:8])
    return src_port, dest_port, length, raw_data[8:]

def is_text_payload(payload):
    if not payload:
        return False
    # Check if payload consists predominantly of printable ASCII characters or common SIP/HTTP line breaks
    text_chars = bytearray({7, 8, 9, 10, 12, 13, 27} | set(range(0x20, 0x100)) - {0x7f})
    return all(b in text_chars for b in payload[:200])

def main():
    if not sys.platform.startswith('linux'):
        print("[!] Note: Raw AF_PACKET sockets require Linux. Run with sudo python3 sip_sniffer.py")
        sys.exit(1)

    iface = sys.argv[1] if len(sys.argv) > 1 else 'any'
    print(f"[*] Starting Linux Raw Socket Sniffer on interface '{iface}'...")
    print("[*] Press Ctrl+C to stop.\n" + "="*70)

    try:
        # AF_PACKET captures all link-layer packets on Linux
        sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
        if iface != 'any':
            sock.bind((iface, 0))
    except PermissionError:
        print("[!] Error: Root privileges required. Please run with 'sudo python3 sip_sniffer.py'")
        sys.exit(1)

    while True:
        try:
            raw_packet, addr = sock.recvfrom(65535)
            dest_mac, src_mac, eth_proto, ip_payload = parse_ethernet_header(raw_packet)

            # Protocol 8 = IPv4
            if eth_proto != 8:
                continue

            version, ip_header_len, ttl, proto_num, src_ip, dest_ip, transport_payload = parse_ip_header(ip_payload)

            src_port = dest_port = 0
            payload = b""

            if proto_num == 6:  # TCP
                src_port, dest_port, seq, ack, tcp_header_len, payload = parse_tcp_header(transport_payload)
                proto_name = "TCP"
            elif proto_num == 17: # UDP
                src_port, dest_port, udp_len, payload = parse_udp_header(transport_payload)
                proto_name = "UDP"
            else:
                continue

            if not payload:
                continue

            # Detect SIP, HTTP, or SDP traffic
            is_sip = b"SIP/2.0" in payload or b"REGISTER" in payload or b"INVITE" in payload or b"BYE" in payload or b"ACK" in payload
            is_http = b"HTTP/1." in payload or b"GET " in payload or b"POST " in payload

            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]

            if is_sip or is_http or is_text_payload(payload):
                tag = "SIP" if is_sip else ("HTTP" if is_http else proto_name)
                print(f"[{timestamp}] [{tag}] {src_ip}:{src_port} -> {dest_ip}:{dest_port}")
                try:
                    text_content = payload.decode('utf-8', errors='replace')
                    for line in text_content.splitlines():
                        if line.strip():
                            print(f"  | {line}")
                except Exception:
                    print(f"  | {payload[:200]}")
                print("-" * 70)

        except KeyboardInterrupt:
            print("\n[*] Sniffer stopped by user.")
            break
        except Exception as e:
            continue

if __name__ == "__main__":
    main()
