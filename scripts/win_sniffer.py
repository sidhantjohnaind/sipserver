import socket
import struct
import sys
import datetime

"""
win_sniffer.py - Pure Python Packet Sniffer for Windows
Captures all SIP (5060, 5061, 5068) and HTTP/ACS (8443) network traffic on Windows.
"""

def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('192.168.29.1', 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

def parse_ip_header(data):
    ver_ihl = data[0]
    ihl = (ver_ihl & 0x0F) * 4
    proto = data[9]
    src_ip = socket.inet_ntoa(data[12:16])
    dst_ip = socket.inet_ntoa(data[16:20])
    return ihl, proto, src_ip, dst_ip, data[ihl:]

def parse_transport_header(proto, data):
    if proto == 6 and len(data) >= 20:  # TCP
        src_port, dst_port = struct.unpack('!HH', data[:4])
        offset = (data[12] >> 4) * 4
        return 'TCP', src_port, dst_port, data[offset:]
    elif proto == 17 and len(data) >= 8: # UDP
        src_port, dst_port, length = struct.unpack('!HHH', data[:6])
        return 'UDP', src_port, dst_port, data[8:]
    return None, 0, 0, b''

def main():
    target_port = int(sys.argv[1]) if len(sys.argv) > 1 else None
    local_ip = get_local_ip()
    print(f"[*] Binding Windows RCVALL socket to local IP: {local_ip}")
    if target_port:
        print(f"[*] Filtering for traffic on Port: {target_port}")
    else:
        print("[*] Filtering for SIP (5060, 5061, 5068) and ACS (8443)...")
    print("[*] Press Ctrl+C to stop.\n" + "="*75)

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_IP)
        s.bind((local_ip, 0))
        s.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
        s.ioctl(socket.SIO_RCVALL, socket.RCVALL_ON)
    except PermissionError:
        print("[!] ERROR: Administrator privileges required!")
        print("[!] Please re-run PowerShell as Administrator.")
        sys.exit(1)
    except Exception as e:
        print(f"[!] Socket initialization error: {e}")
        sys.exit(1)

    packet_count = 0
    match_count = 0

    target_ports = {5060, 5061, 5068, 8443, 80} if not target_port else {target_port}

    while True:
        try:
            raw_data, _ = s.recvfrom(65535)
            packet_count += 1

            if len(raw_data) < 20:
                continue

            ihl, proto, src_ip, dst_ip, payload = parse_ip_header(raw_data)
            proto_name, src_port, dst_port, app_data = parse_transport_header(proto, payload)

            if not proto_name:
                continue

            # Check if matching ports
            if src_port in target_ports or dst_port in target_ports:
                match_count += 1
                timestamp = datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3]
                print(f"\n[{timestamp}] [{proto_name}] {src_ip}:{src_port} -> {dst_ip}:{dst_port} ({len(app_data)} bytes)")
                
                if app_data:
                    # Attempt text decode
                    try:
                        text = app_data.decode('utf-8', errors='replace')
                        clean_lines = [l for l in text.splitlines() if l.strip()]
                        if clean_lines:
                            for line in clean_lines:
                                print(f"  | {line}")
                        else:
                            print(f"  | [Hex/TLS Data: {app_data[:64].hex()}]")
                    except Exception:
                        print(f"  | [Binary Data: {len(app_data)} bytes]")
                print("-" * 75)

        except KeyboardInterrupt:
            print(f"\n[*] Sniffer stopped. (Total Packets Processed: {packet_count}, Matched SIP/ACS: {match_count})")
            try:
                s.ioctl(socket.RCVALL, socket.RCVALL_OFF)
            except Exception:
                pass
            break
        except Exception:
            continue

if __name__ == '__main__':
    main()
