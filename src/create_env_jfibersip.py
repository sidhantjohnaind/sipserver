#!/usr/bin/env python3
"""
JioFiber SIP Proxy .env provisioner (Default Restored Version)
Flow:
- Connects to http://192.168.29.1:8080/request_account to fetch account MSISDN
- Drives OTP verification flow against https://192.168.29.1:8443/ using deterministic MAC
- Fetches SIP config XML from router
- Writes root .env and syncs to executable directories
"""

from __future__ import annotations

import json
import os
import socket
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from typing import Optional, Tuple
from http.cookies import SimpleCookie
import ssl

import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

JIO_DEFAULT_HOST = "192.168.29.1"
REQ_PORT = 8080
IMS_PORT = 8443
HARD_HOSTNAME = "Win11"

# JFC hashing constants/logic
HASH_MULTIPLIER = 33


def calculate_hash(hval: int, key: bytearray) -> int:
    for b in key:
        hval = (hval * HASH_MULTIPLIER) + b
        hval &= 0xFFFFFFFF
    return hval


def convert_to_hex(hval: int) -> str:
    hex_val = f"{hval:08X}"
    return "".join(reversed([hex_val[i : i + 2] for i in range(0, len(hex_val), 2)]))


def get_hash(s: str) -> int:
    return calculate_hash(0, bytearray(s, "utf-8"))


def hex_to_mac(hex_string: str) -> str:
    hex_string = hex_string.zfill(12).lower()
    return ":".join(hex_string[i : i + 2] for i in range(0, len(hex_string), 2))


def mac_from_hostname(hostname: str) -> str:
    h = get_hash(hostname)
    return hex_to_mac(convert_to_hex(h))


class RawResponse:
    def __init__(self, status_code: int, headers: dict[str, str], body: bytes, raw: bytes):
        self.status_code = status_code
        self.headers = headers
        self.text = body.decode(errors="replace")
        self.raw = raw


def raw_https_get(url: str) -> RawResponse:
    parsed = requests.utils.urlparse(url)
    host = parsed.hostname or JIO_DEFAULT_HOST
    port = parsed.port or IMS_PORT
    path = parsed.path or "/"
    q = ("?" + parsed.query) if parsed.query else ""
    full_path = path + q

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    sock = ctx.wrap_socket(socket.create_connection((host, port)), server_hostname=host)
    try:
        req_lines = [
            f"GET {full_path} HTTP/1.1",
            f"Host: {host}",
            "Connection: close",
            "",
            "",
        ]
        sock.sendall("\r\n".join(req_lines).encode())

        resp = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            resp += chunk

        header_blob, body = resp.split(b"\r\n\r\n", 1)
        lines = header_blob.split(b"\r\n")
        status = int(lines[0].split(b" ")[1])
        hdrs: dict[str, str] = {}
        for ln in lines[1:]:
            if b":" in ln:
                k, v = ln.split(b":", 1)
                hdrs[k.decode()] = v.strip().decode()
        return RawResponse(status, hdrs, body, resp)
    finally:
        try:
            sock.close()
        except Exception:
            pass


def resolve_host(host: str) -> Optional[str]:
    try:
        return socket.gethostbyname(host)
    except socket.gaierror:
        return None


def get_local_ipv4() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = "0.0.0.0"
    finally:
        try:
            s.close()
        except Exception:
            pass
    return ip


def request_account(base: str) -> dict:
    url = f"http://{base}:{REQ_PORT}/request_account"
    r = requests.get(url, timeout=5)
    r.raise_for_status()
    return r.json()


def ims_request(base: str, hostname: str, mac: str, add_req: bool, session: Optional[requests.Session] = None):
    url = f"https://{base}:{IMS_PORT}/"
    params = {
        "terminal_sw_version": "RCSAndrd",
        "terminal_vendor": hostname,
        "terminal_model": hostname,
        "SMS_port": 0,
        "act_type": "volatile",
        "IMSI": "",
        "msisdn": "",
        "IMEI": "",
        "vers": 0,
        "token": "",
        "rcs_state": 0,
        "rcs_version": "5.1B",
        "rcs_profile": "joyn_blackbird",
        "client_vendor": "JUIC",
        "default_sms_app": 2,
        "default_vvm_app": 0,
        "device_type": "vvm",
        "client_version": "JSEAndrd-1.0",
        "mac_address": mac,
        "alias": hostname,
        "nwk_intf": "wifi",
    }
    if add_req:
        params["op_type"] = "add"
        get_url = f"{url}?" + "&".join(f"{k}={v}" for k, v in params.items())
        return raw_https_get(get_url)
    client = session or requests
    return client.get(url, params=params, verify=False, timeout=8)


def otp_verify(base: str, otp: int, session: requests.Session):
    url = f"https://{base}:{IMS_PORT}/"
    return session.get(url, params={"OTP": otp}, verify=False, timeout=8)


def fetch_sip_config(base: str, hostname: str, mac: str, session: Optional[requests.Session] = None) -> ET.Element:
    resp = ims_request(base, hostname, mac, add_req=False, session=session)
    resp.raise_for_status()
    return ET.fromstring(resp.text)


def parse_sip_values(root: ET.Element) -> dict:
    wanted = {
        "realm",
        "username",
        "userpwd",
        "home_network_domain_name",
        "address",
        "private_user_identity",
        "public_user_identity",
    }
    out: dict = {}
    for p in root.findall(".//parm"):
        n = p.attrib.get("name")
        v = p.attrib.get("value")
        if n in wanted:
            out[n] = v
    return out


def ensure_endpoint_ready(host_or_ip: Optional[str]) -> Tuple[str, dict]:
    host = host_or_ip or JIO_DEFAULT_HOST
    ip = resolve_host(host)
    if not ip:
        host = "192.168.29.1"
        ip = resolve_host(host)
        if not ip:
            print("Couldn't resolve jiofiber.local.html or 192.168.29.1. Enter your Jio router LAN IP.")
            router_ip = input("Router IP: ").strip()
            if not router_ip:
                fail_prereq()
            host = router_ip
    try:
        acc = request_account(host)
        return host, acc
    except Exception as e:
        print("request_account endpoint not reachable.")
        fail_prereq()
        raise e


def fail_prereq():
    print("\nCannot proceed without access to the Jio router.")
    print("Make sure:")
    print("- You are on the same LAN as the router")
    print("- Router is in AP mode and SIP endpoints are enabled")
    sys.exit(2)


def get_header_case_insensitive(headers: dict[str, str], key: str) -> str:
    key_lower = key.lower()
    for k, v in headers.items():
        if k.lower() == key_lower:
            return v
    return "<unknown>"


def write_env(env_path: str, values: dict):
    lines = [f"{k}={v}" for k, v in values.items()]
    content = "\n".join(lines) + "\n"
    if os.path.exists(env_path):
        try:
            os.replace(env_path, env_path + ".bak")
        except Exception:
            pass
    with open(env_path, "w") as f:
        f.write(content)

    root_dir = os.path.dirname(env_path) if os.path.basename(env_path) == ".env" else env_path
    if not os.path.isdir(root_dir):
        root_dir = os.path.dirname(root_dir)
    for sub in ["bin/windows-x64", "bin/linux-amd64", "bin/linux-arm64"]:
        sdir = os.path.join(root_dir, sub)
        if os.path.exists(sdir):
            try:
                with open(os.path.join(sdir, ".env"), "w") as sf:
                    sf.write(content)
            except Exception:
                pass


def main():
    print("JioFiber SIP Proxy .env provisioner")
    print("This will contact your Jio router to fetch account info and drive OTP.")

    host, acc = ensure_endpoint_ready(None)
    msisdn = acc.get("msisdn")
    if not msisdn:
        print("Unexpected response from request_account; cannot determine msisdn:")
        print(json.dumps(acc, indent=2))
        fail_prereq()

    mac = mac_from_hostname(HARD_HOSTNAME)
    print(f"Using deterministic MAC from hostname '{HARD_HOSTNAME}': {mac}")
    print("Requesting OTP (you will receive an SMS on the Jio number)...")
    sess = requests.Session()
    sess.verify = False
    add_resp = ims_request(host, HARD_HOSTNAME, mac, add_req=True, session=sess)
    if add_resp.status_code != 200:
        print(f"Registration request failed: HTTP {add_resp.status_code}\n{add_resp.text}")
        fail_prereq()

    target_msisdn = get_header_case_insensitive(add_resp.headers, "x-amn")
    print(f"OTP sent to: {target_msisdn}")

    set_cookie_raw = get_header_case_insensitive(add_resp.headers, "Set-Cookie")
    sc = SimpleCookie()
    try:
        sc.load(set_cookie_raw)
    except Exception:
        sc = SimpleCookie()
    fallback_cookie_jar = requests.cookies.cookiejar_from_dict({k: m.value for k, m in sc.items()})

    ok = False
    for attempt in range(3):
        try:
            otp = int(input("Enter OTP: ").strip())
        except Exception:
            print("Invalid OTP format. Use digits only.")
            continue
        verify = otp_verify(host, otp, session=sess)
        if verify.status_code == 200:
            print("OTP verified successfully.")
            ok = True
            break
        else:
            verify2 = requests.get(
                f"https://{host}:{IMS_PORT}/",
                params={"OTP": otp},
                cookies=fallback_cookie_jar,
                verify=False,
                timeout=8,
            )
            if verify2.status_code == 200:
                print("OTP verified successfully (fallback cookies).")
                ok = True
                break
            print(f"OTP failed (HTTP {verify.status_code}/{verify2.status_code}). Try again.")

    if not ok:
        print("Failed to verify OTP after 3 attempts.")
        sys.exit(3)

    root = fetch_sip_config(host, HARD_HOSTNAME, mac, session=sess)
    sip = parse_sip_values(root)
    realm = sip.get("realm", "br.wln.ims.jio.com")
    username = sip.get("username") or f"91{msisdn}@{realm}"
    userpwd = sip.get("userpwd")
    if not userpwd:
        print("Could not obtain SIP password from router config. Aborting.")
        sys.exit(4)

    local_ip = get_local_ipv4()
    clean_num = str(msisdn).replace("+", "").strip()
    if clean_num.startswith("91") and len(clean_num) == 12:
        clean_num = clean_num[2:]

    env_values = {
        "CONTAINER_NAME": "jfc-pjsua",
        "HOSTNAME_OVERRIDE": HARD_HOSTNAME,
        "USER_AGENT": "JSEAndrd-1.0",
        # Local bind/public IP for Contact shaping
        "IPV4_ADDRESS": local_ip,
        "LOCAL_PORT": "5061",
        "TLS_PORT": "5068",
        "RTP_PORT": "52000",
        # SIP/IMS identities
        "PUBLIC_ID": f"sip:+91{clean_num}@{realm}",
        "SIP_AUTH_USER": f"91{clean_num}@{realm}",
        "SIP_PASSWORD": userpwd,
        "SIP_REALM": realm,
        # Upstream proxy/registrar are the router on TLS 5068
        "REGISTRAR_HOST": host,
        "REGISTRAR_PORT": "5068",
        "PROXY_HOST": host,
        "PROXY_PORT": "5068",
        # DNS inside container: prefer router
        "DNS_SERVERS": host,
        # Defaults/tuning
        "LOG_LEVEL": "5",
        "KEEPALIVE": "15",
        "MAX_CALLS": "2",
        # Helpful toggles (can be changed later)
        "TLS_VERIFY": "0",
    }

    repo_root = os.path.dirname(os.path.abspath(__file__))
    env_path = os.path.join(repo_root, ".env")
    write_env(env_path, env_values)

    print("\nWrote .env with the following key values:")
    for k in [
        "HOSTNAME_OVERRIDE",
        "IPV4_ADDRESS",
        "PUBLIC_ID",
        "SIP_AUTH_USER",
        "SIP_REALM",
        "REGISTRAR_HOST",
        "PROXY_HOST",
        "DNS_SERVERS",
        "USER_AGENT",
    ]:
        print(f"- {k}={env_values[k]}")
    print("\nDone. You can now run the proxy with your .env")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted.")
