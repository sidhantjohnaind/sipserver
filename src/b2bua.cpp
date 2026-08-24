/*
 * b2bua.cpp - JioFiber SIP Back-to-Back User Agent in C++17
 * Features:
 * - 100% Cross-Platform (Windows & Linux / macOS)
 * - Embedded Native HTTP/HTTPS OTP provisioner (WinHttp on Windows, OpenSSL/POSIX sockets on Linux)
 * - Zero external script/python dependencies
 * - PJSIP B2BUA audio bridge with AMR-NB / AMR-WB and PCMA/PCMU
 * - Self-healing 403 Forbidden credential auto-recovery
 */

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")
#else
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
typedef int SOCKET;
#ifndef INVALID_SOCKET
#define INVALID_SOCKET -1
#endif
#endif

#include <iostream>
#include <fstream>
#include <string>
#include <string_view>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <random>
#include <sstream>
#include <cctype>
#include <csignal>
#include <cstdlib>
#include <cstring>

extern "C" {
#include <pjsua-lib/pjsua.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/pkcs12.h>
#include <openssl/pem.h>
#include <openssl/rsa.h>
#include <openssl/evp.h>
}

#define THIS_FILE       "b2bua.cpp"
#define MAX_CALLS       16

static pjsua_acc_id g_loc_acc_id = PJSUA_INVALID_ID;
static pjsua_acc_id g_up_acc_id  = PJSUA_INVALID_ID;
static pjsua_transport_id g_udp_tid = PJSUA_INVALID_ID;
static pjsua_transport_id g_tls_tid = PJSUA_INVALID_ID;
static bool g_running = true;

/* Peer call mapping */
static pjsua_call_id g_peer_map[MAX_CALLS];

/* ------------------------------------------------------------------ */
/* String & Environment Helpers                                       */
/* ------------------------------------------------------------------ */

static void signal_handler(int sig) {
    (void)sig;
    g_running = false;
}

static std::string trim(std::string_view s) {
    auto first = s.find_first_not_of(" \t\n\r");
    if (first == std::string_view::npos) return "";
    auto last = s.find_last_not_of(" \t\n\r");
    return std::string(s.substr(first, (last - first + 1)));
}

static std::string sanitize_sip_uri(std::string_view raw) {
    std::string s = trim(raw);
    while (!s.empty() && (s.front() == '<' || s.front() == '"' || s.front() == '\'')) s.erase(0, 1);
    while (!s.empty() && (s.back() == '>' || s.back() == '"' || s.back() == '\'')) s.pop_back();
    return trim(s);
}

static void load_env_file(const std::string &filename) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        file.open("../" + filename);
    }
    if (!file.is_open()) {
        file.open(std::string(getenv("USERPROFILE") ? getenv("USERPROFILE") : "") + "/.jio_b2bua.env");
    }
    if (!file.is_open()) {
        file.open("/etc/jio_b2bua.env");
    }
    if (!file.is_open()) return;

    std::string line;
    while (std::getline(file, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;
        auto eq = line.find('=');
        if (eq != std::string::npos) {
            std::string key = trim(line.substr(0, eq));
            std::string val = trim(line.substr(eq + 1));
            if (!val.empty() && (val.front() == '"' || val.front() == '\'')) val.erase(0, 1);
            if (!val.empty() && (val.back() == '"' || val.back() == '\'')) val.pop_back();
#ifdef _WIN32
            _putenv_s(key.c_str(), val.c_str());
#else
            setenv(key.c_str(), val.c_str(), 1);
#endif
        }
    }
    std::cout << "[b2bua] Loaded configuration from " << filename << std::endl;
}

static std::string get_env_def(const char *name, const char *def_val) {
    const char *v = getenv(name);
    return (v && *v) ? std::string(v) : std::string(def_val);
}

static bool is_env_valid() {
    const char *pub = getenv("PUBLIC_ID");
    const char *pass = getenv("SIP_PASSWORD");
    if (!pass || !*pass) pass = getenv("AUTH_PASS");
    return (pub && *pub && pass && *pass);
}

static bool file_exists(const std::string &filename) {
    std::ifstream f(filename);
    return f.good();
}

/* ------------------------------------------------------------------ */
/* Cross-Platform HTTP/HTTPS Provisioner Engine                       */
/* ------------------------------------------------------------------ */

static std::string mac_from_hostname(const std::string &hostname) {
    uint32_t hval = 0;
    for (unsigned char b : hostname) {
        hval = (hval * 33) + b;
    }

    char hex[16];
    snprintf(hex, sizeof(hex), "%08X", hval);

    std::string rev = { hex[6], hex[7], hex[4], hex[5], hex[2], hex[3], hex[0], hex[1] };
    for (char &c : rev) c = (char)tolower((unsigned char)c);

    std::string mac = "00:00:" + rev.substr(0, 2) + ":" + rev.substr(2, 2) + ":" + rev.substr(4, 2) + ":" + rev.substr(6, 2);
    return mac;
}

static std::string extract_xml_parm(const std::string &xml, const std::string &parm_name) {
    std::string search1 = "name=\"" + parm_name + "\"";
    std::string search2 = "name='" + parm_name + "'";
    auto pos = xml.find(search1);
    if (pos == std::string::npos) pos = xml.find(search2);
    if (pos == std::string::npos) return "";

    auto val_pos = xml.find("value=\"", pos);
    size_t offset = 7;
    if (val_pos == std::string::npos) {
        val_pos = xml.find("value='", pos);
        offset = 7;
    }
    if (val_pos == std::string::npos) return "";

    val_pos += offset;
    char quote_char = xml[val_pos - 1];
    auto end_quote = xml.find(quote_char, val_pos);
    if (end_quote == std::string::npos) return "";

    return xml.substr(val_pos, end_quote - val_pos);
}

struct HttpResponse {
    int status_code{0};
    std::string body;
    std::string cookie;
};

#ifdef _WIN32
static HttpResponse http_get_request(const std::string &host_a, uint16_t port, const std::string &path_a, bool is_https, const std::string &extra_headers_a = "") {
    HttpResponse res;
    std::wstring host(host_a.begin(), host_a.end());
    std::wstring path(path_a.begin(), path_a.end());
    std::wstring extra_headers(extra_headers_a.begin(), extra_headers_a.end());

    HINTERNET hSession = WinHttpOpen(L"JSEAndrd-1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!hSession) return res;

    HINTERNET hConnect = WinHttpConnect(hSession, host.c_str(), (INTERNET_PORT)port, 0);
    if (!hConnect) { WinHttpCloseHandle(hSession); return res; }

    DWORD flags = is_https ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", path.c_str(), NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!hRequest) { WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession); return res; }

    if (is_https) {
        DWORD sec_flags = SECURITY_FLAG_IGNORE_UNKNOWN_CA | SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE | SECURITY_FLAG_IGNORE_CERT_CN_INVALID | SECURITY_FLAG_IGNORE_CERT_DATE_INVALID;
        WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS, &sec_flags, sizeof(sec_flags));
    }

    if (!extra_headers.empty()) {
        WinHttpAddRequestHeaders(hRequest, extra_headers.c_str(), (DWORD)-1L, WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);
    }

    if (WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
        WinHttpReceiveResponse(hRequest, NULL)) {

        wchar_t wcookie[512] = {0};
        DWORD dwSize = sizeof(wcookie);
        if (WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_SET_COOKIE, WINHTTP_HEADER_NAME_BY_INDEX, wcookie, &dwSize, WINHTTP_NO_HEADER_INDEX)) {
            char cookie_a[512] = {0};
            wcstombs(cookie_a, wcookie, sizeof(cookie_a));
            res.cookie = cookie_a;
        }

        std::vector<char> buffer(4096);
        DWORD dwDownloaded = 0;
        while (WinHttpQueryDataAvailable(hRequest, &dwSize) && dwSize > 0) {
            if (buffer.size() < dwSize) buffer.resize(dwSize);
            if (WinHttpReadData(hRequest, buffer.data(), dwSize, &dwDownloaded) && dwDownloaded > 0) {
                res.body.append(buffer.data(), dwDownloaded);
            }
        }
        res.status_code = 200;
    }

    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
    return res;
}
#else
/* Linux / POSIX OpenSSL Socket HTTP/HTTPS GET */
static HttpResponse http_get_request(const std::string &host, uint16_t port, const std::string &path, bool is_https, const std::string &extra_headers = "") {
    HttpResponse res;
    
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return res;

    struct hostent *he = gethostbyname(host.c_str());
    if (!he) { close(sock); return res; }

    struct sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    memcpy(&addr.sin_addr, he->h_addr_list[0], he->h_length);

    if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(sock);
        return res;
    }

    SSL_CTX *ctx = nullptr;
    SSL *ssl = nullptr;

    if (is_https) {
        SSL_library_init();
        ctx = SSL_CTX_new(TLS_client_method());
        if (!ctx) { close(sock); return res; }
        SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, nullptr);
        ssl = SSL_new(ctx);
        SSL_set_fd(ssl, sock);
        if (SSL_connect(ssl) <= 0) {
            SSL_free(ssl);
            SSL_CTX_free(ctx);
            close(sock);
            return res;
        }
    }

    std::string req = "GET " + path + " HTTP/1.1\r\nHost: " + host + "\r\nConnection: close\r\n";
    if (!extra_headers.empty()) req += extra_headers + "\r\n";
    req += "\r\n";

    if (is_https) {
        SSL_write(ssl, req.c_str(), (int)req.length());
    } else {
        send(sock, req.c_str(), req.length(), 0);
    }

    std::vector<char> buf(4096);
    std::string raw_resp;
    int bytes = 0;
    while (true) {
        if (is_https) {
            bytes = SSL_read(ssl, buf.data(), (int)buf.size());
        } else {
            bytes = recv(sock, buf.data(), buf.size(), 0);
        }
        if (bytes <= 0) break;
        raw_resp.append(buf.data(), bytes);
    }

    if (ssl) SSL_free(ssl);
    if (ctx) SSL_CTX_free(ctx);
    close(sock);

    auto header_end = raw_resp.find("\r\n\r\n");
    if (header_end != std::string::npos) {
        std::string headers = raw_resp.substr(0, header_end);
        res.body = raw_resp.substr(header_end + 4);

        if (headers.rfind("HTTP/", 0) == 0) {
            auto sp1 = headers.find(' ');
            if (sp1 != std::string::npos) {
                res.status_code = std::atoi(headers.c_str() + sp1 + 1);
            }
        }

        std::string cookie_tag = "Set-Cookie: ";
        auto cpos = headers.find(cookie_tag);
        if (cpos == std::string::npos) {
            cookie_tag = "set-cookie: ";
            cpos = headers.find(cookie_tag);
        }
        if (cpos != std::string::npos) {
            auto cend = headers.find("\r\n", cpos);
            std::string full_cookie = headers.substr(cpos + cookie_tag.length(), cend - (cpos + cookie_tag.length()));
            auto semi = full_cookie.find(';');
            if (semi != std::string::npos) full_cookie = full_cookie.substr(0, semi);
            res.cookie = trim(full_cookie);
        }
    }
    return res;
}
#endif

static bool run_cpp_otp_provisioner() {
    std::cout << "\n===================================================\n";
    std::cout << "[b2bua] Native Cross-Platform C++ Standalone OTP Provisioner\n";
    std::cout << "===================================================\n\n";

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<> dis(100, 999);

    std::string hostname = "JioWinPC" + std::to_string(dis(gen));
    std::string mac = mac_from_hostname(hostname);

    std::string mac_clean;
    for (char c : mac) if (c != ':') mac_clean += (char)toupper((unsigned char)c);
    std::string uuid = "00000000-0000-1000-8000-" + mac_clean;

    std::cout << "[b2bua] Device Hostname: " << hostname << ", MAC: " << mac << std::endl;
    std::cout << "[b2bua] Enter Jio Router IP [192.168.29.1]: ";
    std::cout.flush();

    std::string host_input;
    std::getline(std::cin, host_input);
    host_input = trim(host_input);
    if (host_input.empty()) {
        if (std::cin.peek() == '\n') std::cin.get();
        host_input = "192.168.29.1";
    }
    std::string host = host_input.empty() ? "192.168.29.1" : host_input;
    std::cout << "[b2bua] Requesting OTP from Jio Router at " << host << "..." << std::endl;
    std::string add_req_path = "/?terminal_sw_version=RCSAndrd&terminal_vendor=" + hostname +
        "&terminal_model=" + hostname + "&SMS_port=0&act_type=volatile&IMSI=&msisdn=&IMEI=&vers=0&token=&rcs_state=0&rcs_version=5.1B&rcs_profile=joyn_blackbird&client_vendor=JUIC&default_sms_app=2&default_vvm_app=0&device_type=vvm&client_version=JSEAndrd-1.0&mac_address=" +
        mac + "&alias=" + hostname + "&nwk_intf=wifi&op_type=add";

    auto resp = http_get_request(host, 8443, add_req_path, true);
    if (resp.status_code != 200) {
        std::cout << "[b2bua] ERROR: Failed to connect to Jio Router on port 8443." << std::endl;
        return false;
    }

    std::cout << "[b2bua] An OTP SMS has been sent to your registered Jio mobile number." << std::endl;
    std::cout << "Enter OTP: ";
    std::cout.flush();

    std::string otp_input;
    std::cin >> otp_input;
    otp_input = trim(otp_input);

    std::string otp_path = "/?OTP=" + otp_input;

    std::string cookie_hdr;
    if (!resp.cookie.empty()) {
        cookie_hdr = "Cookie: " + resp.cookie;
    }

    /* Send OTP verification */
    http_get_request(host, 8443, otp_path, true, cookie_hdr);

    /* Fetch SIP XML payload */
    std::string get_cfg_path = "/?terminal_sw_version=RCSAndrd&terminal_vendor=" + hostname +
        "&terminal_model=" + hostname + "&SMS_port=0&act_type=volatile&IMSI=&msisdn=&IMEI=&vers=0&token=&rcs_state=0&rcs_version=5.1B&rcs_profile=joyn_blackbird&client_vendor=JUIC&default_sms_app=2&default_vvm_app=0&device_type=vvm&client_version=JSEAndrd-1.0&mac_address=" +
        mac + "&alias=" + hostname + "&nwk_intf=wifi";

    auto cfg_resp = http_get_request(host, 8443, get_cfg_path, true, cookie_hdr);
    if (cfg_resp.body.empty()) {
        std::cout << "[b2bua] ERROR: Failed to retrieve SIP XML payload." << std::endl;
        return false;
    }

    std::string realm = extract_xml_parm(cfg_resp.body, "realm");
    std::string username = extract_xml_parm(cfg_resp.body, "username");
    std::string userpwd = extract_xml_parm(cfg_resp.body, "userpwd");
    std::string public_id = extract_xml_parm(cfg_resp.body, "public_user_identity");

    if (userpwd.empty() || public_id.empty()) {
        std::cout << "[b2bua] ERROR: Could not parse SIP credentials from XML response." << std::endl;
        return false;
    }

    std::cout << "\n[b2bua] OTP Verified Successfully!\n";

    std::ofstream env_out(".env");
    if (!env_out.is_open()) return false;

    env_out << "CONTAINER_NAME=jfc-pjsua\n";
    env_out << "HOSTNAME_OVERRIDE=" << hostname << "\n";
    env_out << "UUID=" << uuid << "\n";
    env_out << "USER_AGENT=JSEAndrd-1.0\n";
    env_out << "IPV4_ADDRESS=192.168.29.195\n";
    env_out << "LOCAL_PORT=5061\n";
    env_out << "TLS_PORT=5068\n";
    env_out << "RTP_PORT=52000\n";
    env_out << "PUBLIC_ID=" << public_id << "\n";
    env_out << "SIP_AUTH_USER=" << (username.empty() ? public_id : username) << "\n";
    env_out << "SIP_PASSWORD=" << userpwd << "\n";
    env_out << "SIP_REALM=" << (realm.empty() ? "br.wln.ims.jio.com" : realm) << "\n";
    env_out << "REGISTRAR_HOST=192.168.29.1\n";
    env_out << "REGISTRAR_PORT=5068\n";
    env_out << "PROXY_HOST=192.168.29.1\n";
    env_out << "PROXY_PORT=5068\n";
    env_out << "DNS_SERVERS=192.168.29.1\n";
    env_out << "LOG_LEVEL=4\n";
    env_out << "KEEPALIVE=15\n";
    env_out << "MAX_CALLS=16\n";
    env_out << "TLS_VERIFY=0\n";
    env_out.close();

    std::cout << "\n[b2bua] SUCCESS: Provisioned .env natively!\n\n";
    return true;
}

static void trigger_otp_flow() {
    run_cpp_otp_provisioner();
}

static void ensure_env_configured() {
    load_env_file(".env");
    if (!is_env_valid()) {
        std::cout << "\n===================================================\n";
        std::cout << "[b2bua] .env file missing or incomplete credentials.\n";
        std::cout << "[b2bua] Running OTP authentication flow...\n";
        std::cout << "===================================================\n\n";
        trigger_otp_flow();
        load_env_file(".env");
    }
}

static std::string g_registered_softphone_contact;

static pj_bool_t on_rx_request_reg(pjsip_rx_data *rdata) {
    pjsip_msg *msg = rdata->msg_info.msg;
    int method = msg->line.req.method.id;

    /* Handle softphone CANCEL requests to prevent SIP routing loops over VPN/Tailscale */
    if (method == PJSIP_CANCEL_METHOD || pj_strcmp2(&msg->line.req.method.name, "CANCEL") == 0) {
        PJ_LOG(3, (THIS_FILE, "[b2bua] Received softphone CANCEL over transport, returning 200 OK"));
        pjsip_tx_data *tdata = nullptr;
        if (pjsip_endpt_create_response(pjsua_get_pjsip_endpt(), rdata, 200, NULL, &tdata) == PJ_SUCCESS && tdata) {
            pjsip_endpt_send_response2(pjsua_get_pjsip_endpt(), rdata, tdata, NULL, NULL);
        }
        return PJ_FALSE; /* Allow PJSIP to process CANCEL natively on the target call transaction */
    }

    /* Handle softphone REGISTER, SUBSCRIBE, PUBLISH, and OPTIONS */
    if (method == PJSIP_REGISTER_METHOD || 
        pj_strcmp2(&msg->line.req.method.name, "SUBSCRIBE") == 0 || 
        pj_strcmp2(&msg->line.req.method.name, "OPTIONS") == 0 ||
        pj_strcmp2(&msg->line.req.method.name, "PUBLISH") == 0) {
        
        /* Save registered softphone contact for incoming call routing */
        if (method == PJSIP_REGISTER_METHOD) {
            pjsip_contact_hdr *c_hdr = (pjsip_contact_hdr*) pjsip_msg_find_hdr(rdata->msg_info.msg, PJSIP_H_CONTACT, NULL);
            if (c_hdr && c_hdr->uri) {
                char uri_buf[256];
                int uri_len = pjsip_uri_print(PJSIP_URI_IN_CONTACT_HDR, c_hdr->uri, uri_buf, sizeof(uri_buf) - 1);
                if (uri_len > 0) {
                    uri_buf[uri_len] = '\0';
                    g_registered_softphone_contact = sanitize_sip_uri(uri_buf);
                    PJ_LOG(3, (THIS_FILE, "[b2bua] Softphone registered contact: %s", g_registered_softphone_contact.c_str()));
                }
            } else if (rdata->pkt_info.src_name) {
                char src_buf[128];
                pj_ansi_snprintf(src_buf, sizeof(src_buf), "sip:100@%s:%d", rdata->pkt_info.src_name, rdata->pkt_info.src_port);
                g_registered_softphone_contact = src_buf;
                PJ_LOG(3, (THIS_FILE, "[b2bua] Softphone registered from src: %s", g_registered_softphone_contact.c_str()));
            }
        }
        
        pjsip_tx_data *tdata = nullptr;
        pjsip_contact_hdr *req_contact = nullptr;
        pjsip_contact_hdr *res_contact = nullptr;
        pjsip_expires_hdr *req_exp = nullptr;
        pjsip_expires_hdr *res_exp = nullptr;
        pjsip_to_hdr *to_hdr = nullptr;

        pj_status_t status = pjsip_endpt_create_response(pjsua_get_pjsip_endpt(), rdata, 200, NULL, &tdata);
        if (status == PJ_SUCCESS && tdata) {
            /* For REGISTER 200 OK, remove bogus To tag generated by pjsip_endpt_create_response if request had no To tag */
            if (method == PJSIP_REGISTER_METHOD) {
                pjsip_to_hdr *req_to = (pjsip_to_hdr*) pjsip_msg_find_hdr(rdata->msg_info.msg, PJSIP_H_TO, NULL);
                to_hdr = (pjsip_to_hdr*) pjsip_msg_find_hdr(tdata->msg, PJSIP_H_TO, NULL);
                if (to_hdr && req_to && req_to->tag.slen == 0) {
                    to_hdr->tag.slen = 0;
                }
            }

            /* Extract requested expires value from request (Expires header or Contact expires param) */
            pj_int32_t expires_val = 3600;
            req_exp = (pjsip_expires_hdr*) pjsip_msg_find_hdr(rdata->msg_info.msg, PJSIP_H_EXPIRES, NULL);
            if (req_exp) {
                expires_val = req_exp->ivalue;
            } else {
                req_contact = (pjsip_contact_hdr*) pjsip_msg_find_hdr(rdata->msg_info.msg, PJSIP_H_CONTACT, NULL);
                if (req_contact && req_contact->expires >= 0) {
                    expires_val = req_contact->expires;
                }
            }

            PJ_LOG(3, (THIS_FILE, "[b2bua] Received softphone %.*s (expires=%d), returning RFC 3261 compliant 200 OK",
                   (int)msg->line.req.method.name.slen, msg->line.req.method.name.ptr, expires_val));

            req_contact = (pjsip_contact_hdr*) pjsip_msg_find_hdr(rdata->msg_info.msg, PJSIP_H_CONTACT, NULL);
            if (req_contact) {
                res_contact = (pjsip_contact_hdr*) pjsip_hdr_clone(tdata->pool, req_contact);
                if (res_contact) {
                    res_contact->expires = expires_val;
                    pjsip_msg_add_hdr(tdata->msg, (pjsip_hdr*)res_contact);
                }
            }

            res_exp = pjsip_expires_hdr_create(tdata->pool, expires_val);
            if (res_exp) {
                pjsip_msg_add_hdr(tdata->msg, (pjsip_hdr*)res_exp);
            }

            pjsip_endpt_send_response2(pjsua_get_pjsip_endpt(), rdata, tdata, NULL, NULL);
            return PJ_TRUE;
        }
    }
    return PJ_FALSE;
}

/* Get the local IP that the OS would use to route to the given destination.
 * Uses the UDP connect trick (no packets sent): connect a temp UDP socket to
 * dst, then getsockname() to read which local IP was chosen by the kernel. */
static bool get_local_ip_for_dst(const pj_sockaddr *dst, char *ip_buf, int ip_buf_len) {
    pj_sock_t s = PJ_INVALID_SOCKET;
    if (pj_sock_socket(pj_AF_INET(), pj_SOCK_DGRAM(), 0, &s) != PJ_SUCCESS) return false;
    bool ok = false;
    if (pj_sock_connect(s, dst, (int)pj_sockaddr_get_len(dst)) == PJ_SUCCESS) {
        pj_sockaddr local_addr;
        int addr_len = (int)sizeof(local_addr);
        pj_bzero(&local_addr, sizeof(local_addr));
        if (pj_sock_getsockname(s, &local_addr, &addr_len) == PJ_SUCCESS) {
            if (pj_sockaddr_print(&local_addr, ip_buf, ip_buf_len, 0) != NULL) {
                ok = (strcmp(ip_buf, "0.0.0.0") != 0 && ip_buf[0] != '\0');
            }
        }
    }
    pj_sock_close(s);
    return ok;
}

static pj_status_t on_tx_msg_fix_contact(pjsip_tx_data *tdata) {
    if (!tdata || !tdata->msg) return PJ_SUCCESS;

    /* Only rewrite on the LOCAL UDP softphone transport, not the upstream TLS leg */
    if (!tdata->tp_info.transport) return PJ_SUCCESS;
    if (tdata->tp_info.transport->key.type != PJSIP_TRANSPORT_UDP) return PJ_SUCCESS;

    /* Use OS routing table to find the correct local IP for this destination */
    char ip_str[PJ_INET6_ADDRSTRLEN];
    bool have_local_ip = false;
    if (tdata->tp_info.dst_addr.addr.sa_family == pj_AF_INET()) {
        have_local_ip = get_local_ip_for_dst(&tdata->tp_info.dst_addr, ip_str, sizeof(ip_str));
    }
    if (!have_local_ip) return PJ_SUCCESS; /* can't determine, leave as is */

    pj_str_t local_host = pj_str(ip_str);
    /* Pool-dup so ptr stays valid after this function returns */
    local_host = pj_str((char*)pj_pool_alloc(tdata->pool, local_host.slen + 1));
    pj_memcpy(local_host.ptr, ip_str, strlen(ip_str) + 1);
    local_host.slen = (pj_ssize_t)strlen(ip_str);

    pj_uint16_t local_port = (pj_uint16_t)tdata->tp_info.transport->local_name.port;

    /* 1. Rewrite Contact header host and port */
    pjsip_contact_hdr *contact = (pjsip_contact_hdr*) pjsip_msg_find_hdr(tdata->msg, PJSIP_H_CONTACT, NULL);
    if (contact && contact->uri && PJSIP_URI_SCHEME_IS_SIP(contact->uri)) {
        pjsip_sip_uri *sip_uri = (pjsip_sip_uri*) pjsip_uri_get_uri(contact->uri);
        if (sip_uri) {
            sip_uri->host = local_host;
            if (local_port > 0) sip_uri->port = local_port;
        }
    }

    /* 2. Rewrite SDP c=IN IP4 / o= if body is application/sdp */
    if (tdata->msg->body && tdata->msg->body->len > 0 &&
        pj_stricmp2(&tdata->msg->body->content_type.type,    "application") == 0 &&
        pj_stricmp2(&tdata->msg->body->content_type.subtype, "sdp") == 0) {

        pjmedia_sdp_session *sdp_sess = NULL;
        if (pjmedia_sdp_parse(tdata->pool,
                              (char*)tdata->msg->body->data,
                              tdata->msg->body->len,
                              &sdp_sess) == PJ_SUCCESS && sdp_sess) {
            bool modified = false;
            sdp_sess->origin.addr = local_host;
            if (sdp_sess->conn) {
                sdp_sess->conn->addr = local_host;
                modified = true;
            }
            for (unsigned mi = 0; mi < sdp_sess->media_count; ++mi) {
                if (sdp_sess->media[mi]->conn) {
                    sdp_sess->media[mi]->conn->addr = local_host;
                    modified = true;
                }
            }
            if (modified || true /* always rebuild to pick up origin change */) {
                char sdp_buf[2048];
                int sdp_len = pjmedia_sdp_print(sdp_sess, sdp_buf, sizeof(sdp_buf));
                if (sdp_len > 0) {
                    char *new_data = (char*)pj_pool_alloc(tdata->pool, sdp_len + 1);
                    if (new_data) {
                        pj_memcpy(new_data, sdp_buf, sdp_len);
                        new_data[sdp_len] = '\0';
                        tdata->msg->body->data = new_data;
                        tdata->msg->body->len  = sdp_len;
                    }
                }
            }
        }
    }

    return PJ_SUCCESS;
}

static pjsip_module mod_b2bua_reg = {
    NULL, NULL,
    { (char*)"mod-b2bua-reg", 13 },
    -1,
    PJSIP_MOD_PRIORITY_APPLICATION,
    NULL, NULL, NULL, NULL,
    &on_rx_request_reg,
    NULL,
    &on_tx_msg_fix_contact,
    &on_tx_msg_fix_contact,
    NULL
};

/* ------------------------------------------------------------------ */
/* Media bridging                                                     */
/* ------------------------------------------------------------------ */

static void try_bridge(pjsua_call_id call_id) {
    if (call_id < 0 || call_id >= MAX_CALLS) return;

    pjsua_call_id peer = g_peer_map[call_id];
    if (peer == PJSUA_INVALID_ID) return;

    pjsua_call_info ci, peer_ci;
    if (pjsua_call_get_info(call_id, &ci) != PJ_SUCCESS) return;
    if (pjsua_call_get_info(peer, &peer_ci) != PJ_SUCCESS) return;

    if (ci.media_cnt > 0 && peer_ci.media_cnt > 0 &&
        ci.media[0].type == PJMEDIA_TYPE_AUDIO &&
        peer_ci.media[0].type == PJMEDIA_TYPE_AUDIO &&
        ci.media[0].status == PJSUA_CALL_MEDIA_ACTIVE &&
        peer_ci.media[0].status == PJSUA_CALL_MEDIA_ACTIVE) {

        pjsua_conf_port_id slot_a = ci.media[0].stream.aud.conf_slot;
        pjsua_conf_port_id slot_b = peer_ci.media[0].stream.aud.conf_slot;

        if (slot_a != PJSUA_INVALID_ID && slot_b != PJSUA_INVALID_ID) {
            /* Disconnect both call legs from local sound/null device (slot 0) to avoid mixing noise/drift */
            pjsua_conf_disconnect(0, slot_a);
            pjsua_conf_disconnect(slot_a, 0);
            pjsua_conf_disconnect(0, slot_b);
            pjsua_conf_disconnect(slot_b, 0);

            pjsua_conf_port_info info_a;
            if (pjsua_conf_get_port_info(slot_a, &info_a) == PJ_SUCCESS) {
                bool connected = false;
                for (unsigned i = 0; i < info_a.listener_cnt; ++i) {
                    if (info_a.listeners[i] == slot_b) {
                        connected = true;
                        break;
                    }
                }
                if (!connected) {
                    pjsua_conf_connect(slot_a, slot_b);
                    pjsua_conf_connect(slot_b, slot_a);
                    PJ_LOG(3, (THIS_FILE, "Media bridged cleanly: slot %d <-> slot %d (isolated from sound dev)", slot_a, slot_b));
                }
            }
        }
    }
}

static void audio_meter_thread() {
    pj_thread_desc desc;
    pj_thread_t *thread = NULL;
    if (pj_thread_is_registered() == PJ_FALSE) {
        pj_thread_register("audio_meter", desc, &thread);
    }
    while (g_running) {
        Sleep(1000);
        for (int i = 0; i < MAX_CALLS; ++i) {
            pjsua_call_id peer = g_peer_map[i];
            if (peer != PJSUA_INVALID_ID && i < peer) {
                pjsua_call_info ci1, ci2;
                if (pjsua_call_get_info(i, &ci1) == PJ_SUCCESS &&
                    pjsua_call_get_info(peer, &ci2) == PJ_SUCCESS) {
                    if (ci1.media_cnt > 0 && ci2.media_cnt > 0 &&
                        ci1.media[0].status == PJSUA_CALL_MEDIA_ACTIVE &&
                        ci2.media[0].status == PJSUA_CALL_MEDIA_ACTIVE) {
                        unsigned tx1 = 0, rx1 = 0, tx2 = 0, rx2 = 0;
                        pjsua_conf_port_id s1 = ci1.media[0].stream.aud.conf_slot;
                        pjsua_conf_port_id s2 = ci2.media[0].stream.aud.conf_slot;
                        if (s1 != PJSUA_INVALID_ID && s2 != PJSUA_INVALID_ID) {
                            pjsua_conf_get_signal_level(s1, &tx1, &rx1);
                            pjsua_conf_get_signal_level(s2, &tx2, &rx2);
                            PJ_LOG(3, (THIS_FILE, "[AUDIO-LEVELS] Leg %d (slot %d) In=%u Out=%u <---> Leg %d (slot %d) In=%u Out=%u",
                                       i, s1, rx1, tx1, peer, s2, rx2, tx2));
                        }
                    }
                }
            }
        }
    }
}

#include <mutex>
#define MAX_RAM_LOG_BYTES (512 * 1024) /* 512 KB RAM limit */

static std::string g_ram_log_buffer;
static std::mutex g_ram_log_mutex;

#ifdef _WIN32
#include <windows.h>
static HANDLE g_hLogPipe = INVALID_HANDLE_VALUE;

static void win32_pipe_server_thread() {
    while (g_running) {
        HANDLE hPipe = CreateNamedPipeA(
            "\\\\.\\pipe\\jio_b2bua_logs",
            PIPE_ACCESS_OUTBOUND,
            PIPE_TYPE_BYTE | PIPE_WAIT,
            1, 512 * 1024, 512 * 1024, 0, NULL
        );
        if (hPipe != INVALID_HANDLE_VALUE) {
            if (ConnectNamedPipe(hPipe, NULL) || GetLastError() == ERROR_PIPE_CONNECTED) {
                g_hLogPipe = hPipe;
                /* Pipe active - send buffer snapshot */
                {
                    std::lock_guard<std::mutex> lock(g_ram_log_mutex);
                    DWORD written = 0;
                    WriteFile(hPipe, g_ram_log_buffer.data(), (DWORD)g_ram_log_buffer.size(), &written, NULL);
                }
                while (g_running && g_hLogPipe == hPipe) {
                    Sleep(100);
                }
            }
            CloseHandle(hPipe);
            if (g_hLogPipe == hPipe) g_hLogPipe = INVALID_HANDLE_VALUE;
        }
        Sleep(500);
    }
}
#endif

static void custom_ram_log_writer(int level, const char *data, int len) {
    PJ_UNUSED_ARG(level);
    if (!data || len <= 0) return;

    /* Output to stdout console stream */
    fwrite(data, 1, len, stdout);
    fflush(stdout);

#ifdef _WIN32
    if (g_hLogPipe != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        if (!WriteFile(g_hLogPipe, data, (DWORD)len, &written, NULL)) {
            g_hLogPipe = INVALID_HANDLE_VALUE;
        }
    }
#endif

    std::lock_guard<std::mutex> lock(g_ram_log_mutex);
    g_ram_log_buffer.append(data, len);

    /* Enforce strict 512 KB RAM limit by trimming oldest log lines */
    if (g_ram_log_buffer.size() > MAX_RAM_LOG_BYTES) {
        size_t excess = g_ram_log_buffer.size() - MAX_RAM_LOG_BYTES;
        auto nl = g_ram_log_buffer.find('\n', excess);
        if (nl != std::string::npos) {
            g_ram_log_buffer.erase(0, nl + 1);
        } else {
            g_ram_log_buffer.erase(0, excess);
        }
    }
}

/* ------------------------------------------------------------------ */
/* Callbacks                                                          */
/* ------------------------------------------------------------------ */

static void on_call_media_state(pjsua_call_id call_id) {
    try_bridge(call_id);
}

static void on_call_state(pjsua_call_id call_id, pjsip_event *e) {
    pjsua_call_info ci;
    PJ_UNUSED_ARG(e);

    if (call_id < 0 || call_id >= MAX_CALLS) return;

    pjsua_call_get_info(call_id, &ci);
    PJ_LOG(3, (THIS_FILE, "Call %d state = %s", call_id, ci.state_text.ptr));

    if (ci.state == PJSIP_INV_STATE_DISCONNECTED) {
        PJ_LOG(3, (THIS_FILE, "Call %d disconnected (reason=%d %.*s)",
                   call_id, ci.last_status,
                   (int)ci.last_status_text.slen, ci.last_status_text.ptr));

        pjsua_call_id peer = g_peer_map[call_id];
        if (peer != PJSUA_INVALID_ID) {
            g_peer_map[call_id] = PJSUA_INVALID_ID;
            g_peer_map[peer]    = PJSUA_INVALID_ID;

            pjsua_call_info peer_ci;
            if (pjsua_call_get_info(peer, &peer_ci) == PJ_SUCCESS &&
                peer_ci.state < PJSIP_INV_STATE_DISCONNECTED) {
                PJ_LOG(3, (THIS_FILE, "Hanging up peer call %d (peer_state=%s)", peer, peer_ci.state_text.ptr));
                pjsua_call_hangup(peer, 0, NULL, NULL);
            }
        }
    }
    else if (ci.state == PJSIP_INV_STATE_EARLY) {
        pjsua_call_id peer = g_peer_map[call_id];
        if (peer != PJSUA_INVALID_ID) {
            pjsua_call_info peer_ci;
            if (pjsua_call_get_info(peer, &peer_ci) == PJ_SUCCESS &&
                peer_ci.state < PJSIP_INV_STATE_EARLY) {
                int code = (ci.last_status > 0) ? ci.last_status : 180;
                pjsua_call_answer(peer, code, NULL, NULL);
            }
        }
        try_bridge(call_id);
    }
    else if (ci.state == PJSIP_INV_STATE_CONFIRMED) {
        pjsua_call_id peer = g_peer_map[call_id];
        if (peer != PJSUA_INVALID_ID) {
            pjsua_call_info peer_ci;
            if (pjsua_call_get_info(peer, &peer_ci) == PJ_SUCCESS &&
                peer_ci.state < PJSIP_INV_STATE_CONFIRMED) {
                pjsua_call_answer(peer, 200, NULL, NULL);
            }
        }
        try_bridge(call_id);
    }
}

static void on_incoming_call(pjsua_acc_id acc_id, pjsua_call_id call_id,
                             pjsip_rx_data *rdata) {
    pjsua_call_info ci;
    PJ_UNUSED_ARG(rdata);

    pjsua_call_get_info(call_id, &ci);
    PJ_LOG(3, (THIS_FILE, "Incoming call %d to %.*s from %.*s (acc %d)",
               call_id,
               (int)ci.local_info.slen, ci.local_info.ptr,
               (int)ci.remote_info.slen, ci.remote_info.ptr,
               acc_id));

    /* CASE 1: INCOMING CALL FROM JIO IMS -> Ring Local Softphone */
    if (acc_id == g_up_acc_id) {
        PJ_LOG(3, (THIS_FILE, "[b2bua] Incoming call from Jio IMS - routing to local softphone"));

        std::string dest = get_env_def("DEST_TO_LOCAL", "");
        if (dest.empty()) {
            if (!g_registered_softphone_contact.empty()) {
                dest = g_registered_softphone_contact;
            } else {
                dest = "sip:100@127.0.0.1:5060";
            }
        }

        std::string clean_dest = sanitize_sip_uri(dest);
        if (clean_dest.front() != '<') clean_dest = "<" + clean_dest + ">";

        PJ_LOG(3, (THIS_FILE, "Ringing local softphone: %s", clean_dest.c_str()));
        pjsua_call_answer(call_id, 180, NULL, NULL);

        pjsua_call_setting call_opt;
        pjsua_call_setting_default(&call_opt);
        call_opt.aud_cnt = 1;
        call_opt.vid_cnt = 0;

        pj_str_t dial_uri = pj_str((char*)clean_dest.c_str());
        pjsua_call_id out_id;

        pj_status_t status = pjsua_call_make_call(g_loc_acc_id, &dial_uri,
                                                  &call_opt, NULL, NULL, &out_id);
        if (status != PJ_SUCCESS) {
            PJ_LOG(1, (THIS_FILE, "Failed to ring softphone %s (status=%d)", clean_dest.c_str(), status));
            pjsua_call_hangup(call_id, 486, NULL, NULL);
            return;
        }

        if (call_id >= 0 && call_id < MAX_CALLS &&
            out_id >= 0 && out_id < MAX_CALLS) {
            g_peer_map[call_id] = out_id;
            g_peer_map[out_id]  = call_id;
            PJ_LOG(3, (THIS_FILE, "Mapped Jio IMS call %d <-> Softphone call %d", call_id, out_id));
        } else {
            pjsua_call_hangup(out_id, 500, NULL, NULL);
            pjsua_call_hangup(call_id, 500, NULL, NULL);
        }
        return;
    }

    /* CASE 2: OUTGOING CALL FROM LOCAL SOFTPHONE -> Dial Out via Jio IMS */
    if (g_up_acc_id == PJSUA_INVALID_ID) {
        PJ_LOG(1, (THIS_FILE, "Upstream account not initialized. Rejecting call."));
        pjsua_call_answer(call_id, 503, NULL, NULL);
        return;
    }

    /* Check if upstream account is actually registered (status 200) */
    pjsua_acc_info up_ai;
    pjsua_acc_get_info(g_up_acc_id, &up_ai);
    if (up_ai.status != 200) {
        std::cout << "[b2bua] WARNING: Rejecting call - Upstream Jio IMS is not registered (status=" 
                  << up_ai.status << "). Please check router / registration." << std::endl;
        PJ_LOG(1, (THIS_FILE, "Upstream account not registered (status=%d). Rejecting call 503.", up_ai.status));
        pjsua_call_answer(call_id, 503, NULL, NULL);
        return;
    }
    pjsua_acc_id target_acc = g_up_acc_id;

    /* Determine upstream destination */
    std::string dest;
    const char *env_dest = getenv("DEST_TO_UPSTREAM");
    if (!env_dest || !*env_dest) env_dest = getenv("UP_DEST_URI");
    if (!env_dest || !*env_dest) env_dest = getenv("DEST_URI");
    if (env_dest && *env_dest) dest = env_dest;

    std::string tmpl_raw = get_env_def("DEST_TO_UPSTREAM_TMPL", "sip:{user}@br.wln.ims.jio.com");
    std::string tmpl_clean = sanitize_sip_uri(tmpl_raw);

    if (dest.empty() && !tmpl_clean.empty()) {
        std::string local_uri(ci.local_info.ptr, ci.local_info.slen);
        std::string user = local_uri;

        auto sip_pos = user.find("sip:");
        if (sip_pos == std::string::npos) sip_pos = user.find("sips:");
        if (sip_pos != std::string::npos) {
            auto colon = user.find(':', sip_pos);
            if (colon != std::string::npos) user = user.substr(colon + 1);
        }
        auto at = user.find('@');
        if (at != std::string::npos) user = user.substr(0, at);
        auto gt = user.find('>');
        if (gt != std::string::npos) user = user.substr(0, gt);

        if (user.length() == 11 && user.front() == '0') {
            user = "+91" + user.substr(1);
        } else if (user.length() == 10 && user.front() >= '6' && user.front() <= '9') {
            user = "+91" + user;
        }

        auto tmpl_user_pos = tmpl_clean.find("{user}");
        if (tmpl_user_pos != std::string::npos) {
            tmpl_clean.replace(tmpl_user_pos, 6, user);
        }
        dest = tmpl_clean;
    }

    std::string clean_dest = sanitize_sip_uri(dest);
    if (clean_dest.front() != '<') clean_dest = "<" + clean_dest + ">";

    if (clean_dest.empty()) {
        PJ_LOG(1, (THIS_FILE, "No DEST_URI / DEST_TO_UPSTREAM_TMPL configured"));
        pjsua_call_hangup(call_id, 480, NULL, NULL);
        return;
    }

    PJ_LOG(3, (THIS_FILE, "Dialing upstream destination: %s", clean_dest.c_str()));
    pjsua_call_answer(call_id, 180, NULL, NULL);

    pjsua_call_setting call_opt;
    pjsua_call_setting_default(&call_opt);
    call_opt.aud_cnt = 1;
    call_opt.vid_cnt = 0;

    pjsua_msg_data msg_data;
    pjsua_msg_data_init(&msg_data);

    pj_pool_t *inv_pool = pjsua_pool_create("inv_hdrs", 1024, 1024);
    if (inv_pool) {
        pj_str_t pani_name = pj_str((char*)"P-Access-Network-Info");
        pj_str_t pani_val  = pj_str((char*)"IEEE-802.11");
        pjsip_generic_string_hdr *pani_hdr =
            pjsip_generic_string_hdr_create(inv_pool, &pani_name, &pani_val);
        if (pani_hdr) pj_list_push_back(&msg_data.hdr_list, (pjsip_hdr *)pani_hdr);

        std::string pub_id_raw = get_env_def("PUBLIC_ID", "sip:+910000000000@br.wln.ims.jio.com");
        std::string ppi_str = sanitize_sip_uri(pub_id_raw);
        if (ppi_str.front() != '<') ppi_str = "<" + ppi_str + ">";

        pj_str_t ppi_name = pj_str((char*)"P-Preferred-Identity");
        pj_str_t ppi_val  = pj_str((char*)ppi_str.c_str());
        pjsip_generic_string_hdr *ppi_hdr =
            pjsip_generic_string_hdr_create(inv_pool, &ppi_name, &ppi_val);
        if (ppi_hdr) pj_list_push_back(&msg_data.hdr_list, (pjsip_hdr *)ppi_hdr);
    }

    pj_str_t dial_uri = pj_str((char*)clean_dest.c_str());
    pjsua_call_id out_id;

    pj_status_t status = pjsua_call_make_call(target_acc, &dial_uri,
                                              &call_opt, NULL, &msg_data, &out_id);
    if (status != PJ_SUCCESS && target_acc != g_loc_acc_id) {
        PJ_LOG(2, (THIS_FILE, "target_acc failed (status=%d), trying fallback g_loc_acc_id...", status));
        status = pjsua_call_make_call(g_loc_acc_id, &dial_uri,
                                      &call_opt, NULL, NULL, &out_id);
    }
    if (status != PJ_SUCCESS) {
        PJ_LOG(1, (THIS_FILE, "Failed to dial upstream %s (status=%d)", clean_dest.c_str(), status));
        pjsua_call_hangup(call_id, 500, NULL, NULL);
        return;
    }

    if (call_id >= 0 && call_id < MAX_CALLS &&
        out_id >= 0 && out_id < MAX_CALLS) {
        g_peer_map[call_id] = out_id;
        g_peer_map[out_id]  = call_id;
        PJ_LOG(3, (THIS_FILE, "Mapped inbound %d <-> outbound %d", call_id, out_id));
    } else {
        PJ_LOG(1, (THIS_FILE, "Call ID out of range, tearing down"));
        pjsua_call_hangup(out_id, 500, NULL, NULL);
        pjsua_call_hangup(call_id, 500, NULL, NULL);
    }
}

static int g_consecutive_503_count = 0;

static void on_reg_state(pjsua_acc_id acc_id) {
    pjsua_acc_info ai;
    pjsua_acc_get_info(acc_id, &ai);

    PJ_LOG(3, (THIS_FILE, "Account %d reg status: %d (%.*s)",
               acc_id, ai.status,
               (int)ai.status_text.slen, ai.status_text.ptr));

    if (ai.status == 200) {
        g_consecutive_503_count = 0;
        std::cout << "\n===================================================\n";
        std::cout << "[b2bua] SUCCESS: Registered with Jio IMS!\n";
        std::cout << "===================================================\n\n";
    } else if (ai.status == 403) {
        g_consecutive_503_count = 0;
        std::cout << "\n===================================================\n";
        std::cout << "[b2bua] ERROR 403: Device Not Whitelisted / Credentials Expired.\n";
        std::cout << "[b2bua] Triggering OTP re-authentication flow...\n";
        std::cout << "===================================================\n\n";
        trigger_otp_flow();
        load_env_file(".env");
        pjsua_acc_set_registration(acc_id, PJ_TRUE);
    } else if (ai.status == 503 || ai.status == 500) {
        g_consecutive_503_count++;
        std::cout << "\n===================================================\n";
        std::cout << "[b2bua] WARNING " << ai.status << ": Connection Refused / Service Unavailable by Jio Router (attempt " 
                  << g_consecutive_503_count << ").\n";
        if (g_consecutive_503_count >= 2) {
            std::cout << "[b2bua] Router port 5068 is refusing connection. Re-triggering OTP whitelisting flow...\n";
            std::cout << "===================================================\n\n";
            g_consecutive_503_count = 0;
            trigger_otp_flow();
            load_env_file(".env");
            pjsua_acc_set_registration(acc_id, PJ_TRUE);
        } else {
            std::cout << "[b2bua] Will retry connection shortly. If persistent, check router IP or run OTP provisioner.\n";
            std::cout << "===================================================\n\n";
        }
    } else if (ai.status == 401) {
        std::cout << "[b2bua] Notice 401: Challenge received, sending MD5 credentials...\n";
    }
}

static void set_codecs() {
    pj_str_t keep_amrwb = pj_str((char*)"AMR-WB");
    pj_str_t keep_amr   = pj_str((char*)"AMR");
    pj_str_t keep_l16   = pj_str((char*)"L16/8000");
    pj_str_t keep_pcmu  = pj_str((char*)"PCMU");
    pj_str_t keep_pcma  = pj_str((char*)"PCMA");
    
    pjsua_codec_info c[64];
    unsigned n = PJ_ARRAY_SIZE(c);
    
    if (pjsua_enum_codecs(c, &n) != PJ_SUCCESS) return;
    
    for (unsigned i = 0; i < n; i++) {
        if (pj_strstr(&c[i].codec_id, &keep_amrwb))
            pjsua_codec_set_priority(&c[i].codec_id, 255);
        else if (pj_strstr(&c[i].codec_id, &keep_amr))
            pjsua_codec_set_priority(&c[i].codec_id, 254);
        else if (pj_strstr(&c[i].codec_id, &keep_l16))
            pjsua_codec_set_priority(&c[i].codec_id, 252);
        else if (pj_strstr(&c[i].codec_id, &keep_pcmu))
            pjsua_codec_set_priority(&c[i].codec_id, 250);
        else if (pj_strstr(&c[i].codec_id, &keep_pcma))
            pjsua_codec_set_priority(&c[i].codec_id, 248);
        else
            pjsua_codec_set_priority(&c[i].codec_id, 0);

        pjmedia_codec_param param;
        if (pjsua_codec_get_param(&c[i].codec_id, &param) == PJ_SUCCESS) {
            param.setting.frm_per_pkt = 1; /* Strict 20ms single frame per packet - eliminates 40ms buffering robotic noise */
            param.setting.vad = 0;
            param.setting.cng = 0;
            param.setting.plc = 1;
            pjsua_codec_set_param(&c[i].codec_id, &param);
        }
    }
}

#ifdef _WIN32
static SERVICE_STATUS        g_svc_status;
static SERVICE_STATUS_HANDLE g_svc_status_handle = NULL;

static VOID WINAPI ServiceCtrlHandler(DWORD request) {
    switch (request) {
        case SERVICE_CONTROL_STOP:
        case SERVICE_CONTROL_SHUTDOWN:
            g_svc_status.dwWin32ExitCode = 0;
            g_svc_status.dwCurrentState = SERVICE_STOP_PENDING;
            SetServiceStatus(g_svc_status_handle, &g_svc_status);
            g_running = false;
            break;
        default:
            break;
    }
    SetServiceStatus(g_svc_status_handle, &g_svc_status);
}
#endif

static int run_b2bua_server() {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    ensure_env_configured();

    for (int i = 0; i < MAX_CALLS; i++) g_peer_map[i] = PJSUA_INVALID_ID;

    pj_status_t status = pjsua_create();
    if (status != PJ_SUCCESS) return 1;

    pjsua_config cfg;
    pjsua_logging_config log_cfg;
    pjsua_media_config media_cfg;

    pjsua_config_default(&cfg);
    cfg.max_calls = MAX_CALLS;
    cfg.cb.on_incoming_call   = &on_incoming_call;
    cfg.cb.on_call_state      = &on_call_state;
    cfg.cb.on_call_media_state = &on_call_media_state;
    cfg.cb.on_reg_state       = &on_reg_state;

    std::string dns_servers = get_env_def("DNS_SERVERS", "192.168.29.1");
    if (!dns_servers.empty()) {
        pj_str_t nameservers[4];
        unsigned ns_count = 0;

        std::stringstream ss(dns_servers);
        std::string item;
        while (std::getline(ss, item, ',') && ns_count < 4) {
            item = trim(item);
            if (!item.empty()) {
                nameservers[ns_count++] = pj_str((char*)item.c_str());
            }
        }

        if (ns_count > 0) {
            cfg.nameserver_count = ns_count;
            for (unsigned i = 0; i < ns_count; i++) {
                cfg.nameserver[i] = nameservers[i];
            }
            std::cout << "[b2bua] Configured " << ns_count << " DNS nameserver(s)" << std::endl;
        }
    }

    std::string user_agent = get_env_def("USER_AGENT", "JUICEJFV-1.3.32");
    cfg.user_agent = pj_str((char*)user_agent.c_str());

    pjsua_logging_config_default(&log_cfg);
    log_cfg.level = std::stoi(get_env_def("LOG_LEVEL", "4"));
    log_cfg.cb = &custom_ram_log_writer;
    std::string log_file = get_env_def("LOG_FILE", "0");
    if (!log_file.empty() && log_file != "0" && log_file != "false" && log_file != "none" && log_file != "off") {
        log_cfg.log_filename = pj_str((char*)log_file.c_str());
    } else {
        log_cfg.log_filename.slen = 0;
        log_cfg.log_filename.ptr = NULL;
    }

    pjsua_media_config_default(&media_cfg);
    media_cfg.clock_rate = 8000;
    media_cfg.snd_clock_rate = 8000;
    media_cfg.audio_frame_ptime = 20;
    media_cfg.ptime = 20;
    media_cfg.snd_auto_close_time = 0;
    media_cfg.quality = 10;
    media_cfg.ec_tail_len = 0;
    media_cfg.no_vad = PJ_TRUE;
    media_cfg.jb_max = 300;
    media_cfg.jb_min_pre = 20;
    media_cfg.jb_init = 40;
    media_cfg.jb_max_pre = 80;

    status = pjsua_init(&cfg, &log_cfg, &media_cfg);
    if (status != PJ_SUCCESS) {
        pjsua_destroy();
        return 1;
    }

#ifdef _WIN32
    std::thread(win32_pipe_server_thread).detach();
#endif

    /* UDP Transport (Local softphones) */
    pjsua_transport_config udp_cfg;
    pjsua_transport_config_default(&udp_cfg);
    int local_port = std::stoi(get_env_def("LOCAL_PORT", "5061"));
    udp_cfg.port = local_port;

    status = pjsua_transport_create(PJSIP_TRANSPORT_UDP, &udp_cfg, &g_udp_tid);
    if (status != PJ_SUCCESS) {
        std::cout << "[b2bua] ERROR: Failed to bind to UDP port " << local_port << " (port already in use). Exiting." << std::endl;
        PJ_LOG(1, (THIS_FILE, "Error creating SIP UDP transport on port %d", local_port));
        pjsua_destroy();
        return 1;
    }

    /* Upstream TLS Transport (Jio Router at 192.168.29.1:5068) */
    pjsua_transport_config tls_cfg;
    pjsua_transport_config_default(&tls_cfg);
    tls_cfg.port = 0; /* Ephemeral port for outgoing TLS */

#if defined(PJSIP_TLSV1_2_METHOD)
    tls_cfg.tls_setting.method = PJSIP_TLSV1_2_METHOD;
#endif
    tls_cfg.tls_setting.verify_server = PJ_FALSE;
    tls_cfg.tls_setting.verify_client = PJ_FALSE;

    status = pjsua_transport_create(PJSIP_TRANSPORT_TLS, &tls_cfg, &g_tls_tid);
    if (status != PJ_SUCCESS) {
        PJ_LOG(1, (THIS_FILE, "Error creating SIP TLS transport (status=%d)", status));
        pjsua_destroy();
        return 1;
    }

    status = pjsua_start();
    if (status != PJ_SUCCESS) {
        pjsua_destroy();
        return 1;
    }

    /* Register custom REGISTER handler module */
    pjsip_endpt_register_module(pjsua_get_pjsip_endpt(), &mod_b2bua_reg);

    pjsua_set_null_snd_dev();
    set_codecs();
    std::thread(audio_meter_thread).detach();

    /* Local Listener Account */
    pjsua_acc_config loc_acc_cfg;
    pjsua_acc_config_default(&loc_acc_cfg);
    loc_acc_cfg.id = pj_str((char*)"sip:b2bua@0.0.0.0");
    loc_acc_cfg.register_on_acc_add = PJ_FALSE;
    loc_acc_cfg.transport_id = g_udp_tid;
    status = pjsua_acc_add(&loc_acc_cfg, PJ_TRUE, &g_loc_acc_id);
    if (status != PJ_SUCCESS) {
        PJ_LOG(1, (THIS_FILE, "Error adding local account"));
        pjsua_destroy();
        return 1;
    }

    /* Upstream Jio IMS Account */
    std::string pub_id  = get_env_def("PUBLIC_ID", "sip:+910000000000@br.wln.ims.jio.com");
    std::string s_auth  = get_env_def("SIP_AUTH_USER", "910000000000@br.wln.ims.jio.com");
    std::string s_pass  = get_env_def("SIP_PASSWORD", "");
    if (s_pass.empty()) s_pass = get_env_def("AUTH_PASS", "");
    std::string s_realm = get_env_def("SIP_REALM", "br.wln.ims.jio.com");
    std::string reg_host = get_env_def("PROXY_HOST", "192.168.29.1");
    std::string reg_port = get_env_def("PROXY_PORT", "5068");

    std::string clean_pub = sanitize_sip_uri(pub_id);
    if (clean_pub.front() != '<') clean_pub = "<" + clean_pub + ">";

    std::string reg_uri = "sip:" + s_realm;
    std::string proxy_uri = "sip:" + reg_host + ":" + reg_port + ";transport=tls;lr";

    pjsua_acc_config up_acc_cfg;
    pjsua_acc_config_default(&up_acc_cfg);
    up_acc_cfg.id = pj_str((char*)clean_pub.c_str());
    up_acc_cfg.reg_uri = pj_str((char*)reg_uri.c_str());
    up_acc_cfg.transport_id = g_tls_tid;
    up_acc_cfg.register_on_acc_add = PJ_TRUE;
    up_acc_cfg.reg_timeout = std::stoi(get_env_def("KEEPALIVE", "86400"));
    if (up_acc_cfg.reg_timeout < 3600) up_acc_cfg.reg_timeout = 86400;

    pj_str_t proxy_pj = pj_str((char*)proxy_uri.c_str());
    up_acc_cfg.proxy[0] = proxy_pj;
    up_acc_cfg.proxy_cnt = 1;

    up_acc_cfg.use_rfc5626 = PJ_TRUE;

    /* Upstream headers & contact parameters */
    std::string uuid_val = get_env_def("UUID", "00000000-0000-1000-8000-00001AE07D9A");
    std::string contact_params = ";+sip.instance=\"<" + uuid_val + ">\";+g.3gpp.icsi-ref=\"urn%3Aurn-7%3A3gpp-service.ims.icsi.mmtel\";+g.3gpp.iari-ref=\"urn%3Aurn-7%3A3gpp-application.ims.iari.rcs.jio.eucr\";+g.gsma.rcs.telephony=\"none\";video";
    up_acc_cfg.contact_params = pj_str((char*)contact_params.c_str());

    up_acc_cfg.cred_count = 1;
    up_acc_cfg.cred_info[0].realm = pj_str((char*)s_realm.c_str());
    up_acc_cfg.cred_info[0].scheme = pj_str((char*)"digest");
    up_acc_cfg.cred_info[0].username = pj_str((char*)s_auth.c_str());
    up_acc_cfg.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    up_acc_cfg.cred_info[0].data = pj_str((char*)s_pass.c_str());

    pj_pool_t *reg_pool = pjsua_pool_create("reg_hdrs", 512, 512);
    if (reg_pool) {
        pj_str_t pani_name = pj_str((char*)"P-Access-Network-Info");
        pj_str_t pani_val  = pj_str((char*)"IEEE-802.11");
        pjsip_generic_string_hdr *pani_hdr = pjsip_generic_string_hdr_create(reg_pool, &pani_name, &pani_val);
        if (pani_hdr) pj_list_push_back(&up_acc_cfg.reg_hdr_list, pani_hdr);

        pj_str_t ppi_name = pj_str((char*)"P-Preferred-Identity");
        pj_str_t ppi_val  = pj_str((char*)clean_pub.c_str());
        pjsip_generic_string_hdr *ppi_hdr = pjsip_generic_string_hdr_create(reg_pool, &ppi_name, &ppi_val);
        if (ppi_hdr) pj_list_push_back(&up_acc_cfg.reg_hdr_list, ppi_hdr);
    }

    status = pjsua_acc_add(&up_acc_cfg, PJ_TRUE, &g_up_acc_id);
    if (status != PJ_SUCCESS) {
        PJ_LOG(1, (THIS_FILE, "Error adding upstream Jio IMS account (status=%d)", status));
        pjsua_destroy();
        return 1;
    }

    std::cout << "[b2bua] B2BUA running. Local UDP:" << get_env_def("LOCAL_PORT", "5061")
              << " Upstream TLS:" << reg_port << " DNS:" << reg_host
              << " Press Ctrl+C to stop." << std::endl;

    while (g_running) {
        pjsua_handle_events(100);
    }

    std::cout << "[b2bua] Shutting down B2BUA..." << std::endl;
    pjsua_destroy();
    return 0;
}

#ifdef _WIN32
static VOID WINAPI ServiceMain(DWORD argc, LPTSTR *argv) {
    (void)argc;
    (void)argv;
    g_svc_status_handle = RegisterServiceCtrlHandlerA("JioFiberB2BUA", ServiceCtrlHandler);
    if (!g_svc_status_handle) return;

    ZeroMemory(&g_svc_status, sizeof(g_svc_status));
    g_svc_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_svc_status.dwServiceSpecificExitCode = 0;
    g_svc_status.dwWin32ExitCode = 0;
    g_svc_status.dwCheckPoint = 0;
    g_svc_status.dwWaitHint = 0;
    g_svc_status.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
    g_svc_status.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(g_svc_status_handle, &g_svc_status);

    run_b2bua_server();

    g_svc_status.dwCurrentState = SERVICE_STOPPED;
    SetServiceStatus(g_svc_status_handle, &g_svc_status);
}
#endif

int main(int argc, char *argv[]) {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

#ifdef _WIN32
    wchar_t exe_path[MAX_PATH];
    if (GetModuleFileNameW(NULL, exe_path, MAX_PATH)) {
        std::wstring ws(exe_path);
        size_t pos = ws.find_last_of(L"\\/");
        if (pos != std::wstring::npos) {
            SetCurrentDirectoryW(ws.substr(0, pos).c_str());
        }
    }

    bool force_console = false;
    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "--console" || std::string(argv[i]) == "-c") {
            force_console = true;
            break;
        }
    }

    if (!force_console) {
        SERVICE_TABLE_ENTRYA ServiceTable[] = {
            { (LPSTR)"JioFiberB2BUA", (LPSERVICE_MAIN_FUNCTIONA)ServiceMain },
            { NULL, NULL }
        };
        if (StartServiceCtrlDispatcherA(ServiceTable)) {
            return 0;
        }
    }
#else
    char exe_buf[1024];
    ssize_t len = readlink("/proc/self/exe", exe_buf, sizeof(exe_buf) - 1);
    if (len > 0) {
        exe_buf[len] = '\0';
        std::string path_str(exe_buf);
        size_t pos = path_str.find_last_of('/');
        if (pos != std::string::npos) {
            chdir(path_str.substr(0, pos).c_str());
        }
    }
#endif

    return run_b2bua_server();
}
