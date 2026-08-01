/*
 * b2bua.c - JioFiber SIP Back-to-Back User Agent (PJSIP / PJSUA 2.x)
 * Fixed for TLS, bypass verification, DNS resolution via router, proper URI sanitization,
 * sound device bypass, and B2BUA bridging.
 */

#include <pjsua-lib/pjsua.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <signal.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

#define THIS_FILE       "b2bua.c"
#define MAX_CALLS       16

static pjsua_acc_id g_loc_acc_id = PJSUA_INVALID_ID;
static pjsua_acc_id g_up_acc_id  = PJSUA_INVALID_ID;
static pjsua_transport_id g_udp_tid = PJSUA_INVALID_ID;
static pjsua_transport_id g_tls_tid = PJSUA_INVALID_ID;
static pj_bool_t g_running = PJ_TRUE;

/* Peer mapping: index = call_id, value = peer call_id or PJSUA_INVALID_ID */
static pjsua_call_id g_peer_map[MAX_CALLS];

/* ------------------------------------------------------------------ */
/* Helpers                                                            */
/* ------------------------------------------------------------------ */

static void signal_handler(int sig) {
    PJ_UNUSED_ARG(sig);
    g_running = PJ_FALSE;
}

static char *trim_str(char *str) {
    char *end;
    while (isspace((unsigned char)*str)) str++;
    if (*str == 0) return str;
    end = str + strlen(str) - 1;
    while (end > str && isspace((unsigned char)*end)) end--;
    end[1] = '\0';
    return str;
}

/* Sanitize SIP URI: strips surrounding <>, quotes, and whitespace */
static char *sanitize_sip_uri(char *buf, size_t buf_size, const char *raw) {
    if (!raw || !*raw) {
        buf[0] = '\0';
        return buf;
    }
    const char *start = raw;
    while (isspace((unsigned char)*start) || *start == '<' || *start == '"' || *start == '\'') start++;
    
    size_t len = strlen(start);
    while (len > 0 && (isspace((unsigned char)start[len-1]) || start[len-1] == '>' || start[len-1] == '"' || start[len-1] == '\'')) {
        len--;
    }
    
    if (len >= buf_size) len = buf_size - 1;
    memcpy(buf, start, len);
    buf[len] = '\0';
    return buf;
}

static void load_env_file(const char *filename) {
    char env_path[512] = {0};

#ifdef _WIN32
    char exe_path[512] = {0};
    GetModuleFileNameA(NULL, exe_path, sizeof(exe_path));
    char *last_slash = strrchr(exe_path, '\\');
    if (last_slash) {
        *last_slash = '\0';
        snprintf(env_path, sizeof(env_path), "%s\\%s", exe_path, filename);
    } else {
        snprintf(env_path, sizeof(env_path), "%s", filename);
    }
#else
    char exe_path[512] = {0};
    ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
    if (len != -1) {
        exe_path[len] = '\0';
        char *last_slash = strrchr(exe_path, '/');
        if (last_slash) {
            *last_slash = '\0';
            snprintf(env_path, sizeof(env_path), "%s/%s", exe_path, filename);
        } else {
            snprintf(env_path, sizeof(env_path), "%s", filename);
        }
    } else {
        snprintf(env_path, sizeof(env_path), "%s", filename);
    }
#endif

    FILE *f = fopen(env_path, "r");
    if (!f) f = fopen(filename, "r");
    if (!f) f = fopen("../.env", "r");
    if (!f) return;

    char line[512];
    while (fgets(line, sizeof(line), f)) {
        char *l = trim_str(line);
        if (l[0] == '#' || l[0] == '\0') continue;

        char *eq = strchr(l, '=');
        if (!eq) continue;

        *eq = '\0';
        char *key = trim_str(l);
        char *val = trim_str(eq + 1);

        size_t vlen = strlen(val);
        if (vlen >= 2 && ((val[0] == '"' && val[vlen-1] == '"') ||
                          (val[0] == '\'' && val[vlen-1] == '\''))) {
            val[vlen-1] = '\0';
            val++;
        }

        if (*key && *val) {
#ifdef _WIN32
            char envbuf[512];
            snprintf(envbuf, sizeof(envbuf), "%s=%s", key, val);
            _putenv(_strdup(envbuf));
#else
            setenv(key, val, 1);
#endif
        }
    }
    fclose(f);
    printf("[b2bua] Loaded configuration from %s\n", filename);
}

static const char *get_env_def(const char *name, const char *def_val) {
    const char *v = getenv(name);
    return (v && *v) ? v : def_val;
}

static pj_bool_t is_env_valid(void) {
    const char *pub = getenv("PUBLIC_ID");
    const char *pass = getenv("SIP_PASSWORD");
    if (!pass || !*pass) pass = getenv("AUTH_PASS");
    return (pub && *pub && pass && *pass) ? PJ_TRUE : PJ_FALSE;
}

#ifdef _WIN32
#include <winhttp.h>

static void mac_from_hostname(const char *hostname, char *out_mac, size_t max_len) {
    unsigned int hval = 0;
    const unsigned char *p = (const unsigned char*)hostname;
    while (*p) {
        hval = (hval * 33) + *p;
        hval &= 0xFFFFFFFF;
        p++;
    }
    char hex[16];
    snprintf(hex, sizeof(hex), "%08X", hval);
    char rev[16];
    rev[0] = hex[6]; rev[1] = hex[7];
    rev[2] = hex[4]; rev[3] = hex[5];
    rev[4] = hex[2]; rev[5] = hex[3];
    rev[6] = hex[0]; rev[7] = hex[1];
    rev[8] = '\0';
    snprintf(out_mac, max_len, "00:00:%c%c:%c%c:%c%c:%c%c",
             tolower((unsigned char)rev[0]), tolower((unsigned char)rev[1]),
             tolower((unsigned char)rev[2]), tolower((unsigned char)rev[3]),
             tolower((unsigned char)rev[4]), tolower((unsigned char)rev[5]),
             tolower((unsigned char)rev[6]), tolower((unsigned char)rev[7]));
}

static int extract_xml_parm(const char *xml, const char *parm_name, char *out_val, size_t max_len) {
    char search_str[128];
    const char *pos = NULL;
    const char *val_pos = NULL;
    const char *end_quote = NULL;
    size_t len = 0;

    snprintf(search_str, sizeof(search_str), "name=\"%s\"", parm_name);
    pos = strstr(xml, search_str);
    if (!pos) {
        snprintf(search_str, sizeof(search_str), "name='%s'", parm_name);
        pos = strstr(xml, search_str);
    }
    if (!pos) return 0;
    
    val_pos = strstr(pos, "value=\"");
    if (!val_pos) {
        val_pos = strstr(pos, "value='");
    }
    if (!val_pos) return 0;
    
    val_pos += 7;
    end_quote = strchr(val_pos, val_pos[-1]);
    if (!end_quote) return 0;
    
    len = end_quote - val_pos;
    if (len >= max_len) len = max_len - 1;
    memcpy(out_val, val_pos, len);
    out_val[len] = '\0';
    return 1;
}

static int http_get_request(const wchar_t *host, INTERNET_PORT port, const wchar_t *path, int is_https, const wchar_t *extra_headers, char *out_buf, size_t max_buf, char *out_cookie, size_t max_cookie) {
    HINTERNET hSession = NULL, hConnect = NULL, hRequest = NULL;
    DWORD flags = 0, sec_flags = 0, dwSize = 0, dwDownloaded = 0;
    size_t total_read = 0;
    wchar_t wcookie[512] = {0};

    hSession = WinHttpOpen(L"JSEAndrd-1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!hSession) return 0;

    hConnect = WinHttpConnect(hSession, host, port, 0);
    if (!hConnect) { WinHttpCloseHandle(hSession); return 0; }

    flags = is_https ? WINHTTP_FLAG_SECURE : 0;
    hRequest = WinHttpOpenRequest(hConnect, L"GET", path, NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!hRequest) { WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession); return 0; }

    if (is_https) {
        sec_flags = SECURITY_FLAG_IGNORE_UNKNOWN_CA | SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE | SECURITY_FLAG_IGNORE_CERT_CN_INVALID | SECURITY_FLAG_IGNORE_CERT_DATE_INVALID;
        WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS, &sec_flags, sizeof(sec_flags));
    }

    if (extra_headers) {
        WinHttpAddRequestHeaders(hRequest, extra_headers, (DWORD)-1L, WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);
    }

    if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) ||
        !WinHttpReceiveResponse(hRequest, NULL)) {
        WinHttpCloseHandle(hRequest); WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession);
        return 0;
    }

    if (out_cookie && max_cookie > 0) {
        dwSize = (DWORD)sizeof(wcookie);
        if (WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_SET_COOKIE, WINHTTP_HEADER_NAME_BY_INDEX, wcookie, &dwSize, WINHTTP_NO_HEADER_INDEX)) {
            wcstombs(out_cookie, wcookie, max_cookie);
        }
    }

    out_buf[0] = '\0';
    do {
        dwSize = 0;
        if (!WinHttpQueryDataAvailable(hRequest, &dwSize)) break;
        if (dwSize == 0) break;

        if (total_read + dwSize >= max_buf) dwSize = (DWORD)(max_buf - total_read - 1);
        if (dwSize == 0) break;

        if (!WinHttpReadData(hRequest, out_buf + total_read, dwSize, &dwDownloaded)) break;
        total_read += dwDownloaded;
    } while (dwSize > 0);

    out_buf[total_read] = '\0';

    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
    return (int)total_read;
}

static int run_c_otp_provisioner(void) {
    wchar_t router_host[128] = L"192.168.29.1";
    char router_host_a[128] = "192.168.29.1";
    char hostname[64];
    char mac[32];
    char uuid[64];
    char mac_no_colons[16] = {0};
    wchar_t add_req_path[1024];
    char resp_buf[16384] = {0};
    char cookie_buf[512] = {0};
    char otp_str[32] = {0};
    wchar_t otp_path[256];
    wchar_t cookie_hdr[512] = {0};
    wchar_t get_cfg_path[1024];
    char realm[128] = {0};
    char username[128] = {0};
    char userpwd[128] = {0};
    char public_id[128] = {0};
    FILE *f = NULL;
    int rand_id = 0;
    int idx = 0, i = 0, bytes = 0;

    printf("\n===================================================\n");
    printf("[b2bua] Native Standalone C OTP Provisioner\n");
    printf("===================================================\n\n");

    rand_id = (rand() % 900) + 100;
    snprintf(hostname, sizeof(hostname), "JioWinPC%d", rand_id);
    mac_from_hostname(hostname, mac, sizeof(mac));

    for (i = 0; mac[i]; i++) {
        if (mac[i] != ':') mac_no_colons[idx++] = toupper((unsigned char)mac[i]);
    }
    snprintf(uuid, sizeof(uuid), "00000000-0000-1000-8000-%012s", mac_no_colons);

    printf("[b2bua] Device Hostname: %s, MAC: %s\n", hostname, mac);
    printf("[b2bua] Requesting OTP from Jio Router at %s...\n", router_host_a);

    swprintf(add_req_path, sizeof(add_req_path)/sizeof(wchar_t),
        L"/?terminal_sw_version=RCSAndrd&terminal_vendor=%S&terminal_model=%S&SMS_port=0&act_type=volatile&IMSI=&msisdn=&IMEI=&vers=0&token=&rcs_state=0&rcs_version=5.1B&rcs_profile=joyn_blackbird&client_vendor=JUIC&default_sms_app=2&default_vvm_app=0&device_type=vvm&client_version=JSEAndrd-1.0&mac_address=%S&alias=%S&nwk_intf=wifi&op_type=add",
        hostname, hostname, mac, hostname);

    bytes = http_get_request(router_host, 8443, add_req_path, 1, NULL, resp_buf, sizeof(resp_buf), cookie_buf, sizeof(cookie_buf));
    if (bytes <= 0) {
        printf("[b2bua] Failed to connect to Jio router HTTPS service.\n");
        return 0;
    }

    printf("[b2bua] OTP SMS has been sent to your registered Jio mobile number.\n");
    printf("Enter OTP: ");
    fflush(stdout);

    if (!fgets(otp_str, sizeof(otp_str), stdin)) return 0;
    char *p = otp_str;
    while (*p && isspace((unsigned char)*p)) p++;
    char *end = p + strlen(p) - 1;
    while (end > p && isspace((unsigned char)*end)) *end-- = '\0';

    swprintf(otp_path, sizeof(otp_path)/sizeof(wchar_t), L"/?OTP=%S", p);
    if (cookie_buf[0]) {
        swprintf(cookie_hdr, sizeof(cookie_hdr)/sizeof(wchar_t), L"Cookie: %S", cookie_buf);
    }

    /* Send OTP verify */
    http_get_request(router_host, 8443, otp_path, 1, cookie_hdr[0] ? cookie_hdr : NULL, resp_buf, sizeof(resp_buf), NULL, 0);

    /* Fetch SIP XML payload */
    swprintf(get_cfg_path, sizeof(get_cfg_path)/sizeof(wchar_t),
        L"/?terminal_sw_version=RCSAndrd&terminal_vendor=%S&terminal_model=%S&SMS_port=0&act_type=volatile&IMSI=&msisdn=&IMEI=&vers=0&token=&rcs_state=0&rcs_version=5.1B&rcs_profile=joyn_blackbird&client_vendor=JUIC&default_sms_app=2&default_vvm_app=0&device_type=vvm&client_version=JSEAndrd-1.0&mac_address=%S&alias=%S&nwk_intf=wifi",
        hostname, hostname, mac, hostname);

    bytes = http_get_request(router_host, 8443, get_cfg_path, 1, cookie_hdr[0] ? cookie_hdr : NULL, resp_buf, sizeof(resp_buf), NULL, 0);
    if (bytes <= 0) {
        printf("[b2bua] ERROR: Failed to read SIP XML payload.\n");
        return 0;
    }

    extract_xml_parm(resp_buf, "realm", realm, sizeof(realm));
    extract_xml_parm(resp_buf, "username", username, sizeof(username));
    extract_xml_parm(resp_buf, "userpwd", userpwd, sizeof(userpwd));
    extract_xml_parm(resp_buf, "public_user_identity", public_id, sizeof(public_id));

    if (!userpwd[0] || !public_id[0]) {
        printf("[b2bua] ERROR: Could not parse SIP credentials from XML response.\n");
        return 0;
    }

    f = fopen(".env", "w");
    if (!f) return 0;

    fprintf(f, "CONTAINER_NAME=jfc-pjsua\n");
    fprintf(f, "HOSTNAME_OVERRIDE=%s\n", hostname);
    fprintf(f, "UUID=%s\n", uuid);
    fprintf(f, "USER_AGENT=JSEAndrd-1.0\n");
    fprintf(f, "IPV4_ADDRESS=192.168.29.195\n");
    fprintf(f, "LOCAL_PORT=5061\n");
    fprintf(f, "TLS_PORT=5068\n");
    fprintf(f, "RTP_PORT=52000\n");
    fprintf(f, "PUBLIC_ID=%s\n", public_id);
    fprintf(f, "SIP_AUTH_USER=%s\n", username[0] ? username : public_id);
    fprintf(f, "SIP_PASSWORD=%s\n", userpwd);
    fprintf(f, "SIP_REALM=%s\n", realm[0] ? realm : "br.wln.ims.jio.com");
    fprintf(f, "REGISTRAR_HOST=%s\n", router_host_a);
    fprintf(f, "REGISTRAR_PORT=5068\n");
    fprintf(f, "PROXY_HOST=%s\n", router_host_a);
    fprintf(f, "PROXY_PORT=5068\n");
    fprintf(f, "DNS_SERVERS=%s\n", router_host_a);
    fprintf(f, "LOG_LEVEL=4\n");
    fprintf(f, "KEEPALIVE=15\n");
    fprintf(f, "MAX_CALLS=16\n");
    fprintf(f, "TLS_VERIFY=0\n");
    fclose(f);

    printf("\n[b2bua] SUCCESS: Provisioned .env natively in C!\n\n");
    return 1;
}
#endif

static void trigger_otp_flow(void) {
#ifdef _WIN32
    run_c_otp_provisioner();
#else
    int res = system("python3 create_env_jfibersip.py");
    if (res != 0) system("python create_env_jfibersip.py");
#endif
}

static void ensure_env_configured(void) {
    load_env_file(".env");
    if (!is_env_valid()) {
        printf("\n===================================================\n");
        printf("[b2bua] .env file missing or incomplete credentials.\n");
        printf("[b2bua] Running OTP authentication flow...\n");
        printf("===================================================\n\n");
        trigger_otp_flow();
        load_env_file(".env");
    }
}

/* ------------------------------------------------------------------ */
/* Custom SIP Module for softphone REGISTER handling                  */
/* ------------------------------------------------------------------ */

static pj_bool_t on_rx_request_reg(pjsip_rx_data *rdata) {
    if (rdata->msg_info.msg->line.req.method.id == PJSIP_REGISTER_METHOD) {
        pjsip_tx_data *tdata = NULL;
        pjsip_contact_hdr *req_contact = NULL;
        pjsip_contact_hdr *res_contact = NULL;
        pjsip_expires_hdr *exp_hdr = NULL;
        pj_status_t status;

        PJ_LOG(3, (THIS_FILE, "[b2bua] Received REGISTER from softphone, answering 200 OK with Contact & Expires headers"));

        status = pjsip_endpt_create_response(pjsua_get_pjsip_endpt(), rdata, 200, NULL, &tdata);
        if (status == PJ_SUCCESS && tdata) {
            req_contact = (pjsip_contact_hdr*) pjsip_msg_find_hdr(rdata->msg_info.msg, PJSIP_H_CONTACT, NULL);
            if (req_contact) {
                res_contact = (pjsip_contact_hdr*) pjsip_hdr_clone(tdata->pool, req_contact);
                if (res_contact) {
                    res_contact->expires = 3600;
                    pjsip_msg_add_hdr(tdata->msg, (pjsip_hdr*)res_contact);
                }
            }

            exp_hdr = pjsip_expires_hdr_create(tdata->pool, 3600);
            if (exp_hdr) {
                pjsip_msg_add_hdr(tdata->msg, (pjsip_hdr*)exp_hdr);
            }

            pjsip_endpt_send_response2(pjsua_get_pjsip_endpt(), rdata, tdata, NULL, NULL);
            return PJ_TRUE;
        }
    }
    return PJ_FALSE;
}

static pjsip_module mod_b2bua_reg = {
    NULL, NULL,
    { "mod-b2bua-reg", 13 },
    -1,
    PJSIP_MOD_PRIORITY_APPLICATION,
    NULL, NULL, NULL, NULL,
    &on_rx_request_reg,
    NULL, NULL, NULL,
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
            pjsua_conf_port_info info_a;
            if (pjsua_conf_get_port_info(slot_a, &info_a) == PJ_SUCCESS) {
                pj_bool_t connected = PJ_FALSE;
                unsigned i;
                for (i = 0; i < info_a.listener_cnt; ++i) {
                    if (info_a.listeners[i] == slot_b) {
                        connected = PJ_TRUE;
                        break;
                    }
                }
                if (!connected) {
                    pjsua_conf_connect(slot_a, slot_b);
                    pjsua_conf_connect(slot_b, slot_a);
                    PJ_LOG(3, (THIS_FILE, "Media bridged: slot %d <-> slot %d", slot_a, slot_b));
                }
            }
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
                int code = (ci.last_status > 0) ? ci.last_status : 200;
                pjsua_call_hangup(peer, code, NULL, NULL);
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

    if (g_up_acc_id == PJSUA_INVALID_ID) {
        PJ_LOG(1, (THIS_FILE, "Upstream account not registered. Rejecting call."));
        pjsua_call_answer(call_id, 503, NULL, NULL);
        return;
    }
    pjsua_acc_id target_acc = g_up_acc_id;

    /* ---- Determine upstream destination ---- */
    const char *dest = NULL;
    char dest_buf[512];

    dest = getenv("DEST_TO_UPSTREAM");
    if (!dest || !*dest) dest = getenv("UP_DEST_URI");
    if (!dest || !*dest) dest = getenv("DEST_URI");

    const char *tmpl_raw = getenv("DEST_TO_UPSTREAM_TMPL");
    char tmpl_clean[256];
    if (!tmpl_raw || !*tmpl_raw) {
        snprintf(tmpl_clean, sizeof(tmpl_clean), "sip:{user}@br.wln.ims.jio.com");
    } else {
        sanitize_sip_uri(tmpl_clean, sizeof(tmpl_clean), tmpl_raw);
    }

    if ((!dest || !*dest) && tmpl_clean[0]) {
        char local_uri[256];
        int n = (ci.local_info.slen < (int)sizeof(local_uri)-1)
                    ? ci.local_info.slen : (int)sizeof(local_uri)-1;
        memcpy(local_uri, ci.local_info.ptr, n);
        local_uri[n] = '\0';

        char *user = local_uri;
        char *sip_ptr = strstr(user, "sip:");
        if (!sip_ptr) sip_ptr = strstr(user, "sips:");
        if (sip_ptr) {
            user = strchr(sip_ptr, ':');
            if (user) ++user;
        }
        char *at = strchr(user, '@');
        if (at) *at = '\0';
        char *gt = strchr(user, '>');
        if (gt) *gt = '\0';

        char norm_user[64];
        if (user[0] == '0' && strlen(user) == 11) {
            snprintf(norm_user, sizeof(norm_user), "+91%s", user + 1);
            user = norm_user;
        } else if (strlen(user) == 10 && user[0] >= '6' && user[0] <= '9') {
            snprintf(norm_user, sizeof(norm_user), "+91%s", user);
            user = norm_user;
        }

        const char *p = tmpl_clean;
        char *out = dest_buf;
        size_t rem = sizeof(dest_buf) - 1;
        while (*p && rem > 0) {
            if (strncmp(p, "{user}", 6) == 0) {
                size_t ulen = strlen(user);
                if (ulen > rem) ulen = rem;
                memcpy(out, user, ulen);
                out += ulen;
                rem -= ulen;
                p += 6;
            } else {
                *out++ = *p++;
                rem--;
            }
        }
        *out = '\0';
        dest = dest_buf;
    }

    char clean_dest[512];
    if (dest[0] != '<') {
        snprintf(clean_dest, sizeof(clean_dest), "<%s>", dest);
    } else {
        snprintf(clean_dest, sizeof(clean_dest), "%s", dest);
    }

    if (!clean_dest[0]) {
        PJ_LOG(1, (THIS_FILE, "No DEST_URI / DEST_TO_UPSTREAM_TMPL configured"));
        pjsua_call_hangup(call_id, 480, NULL, NULL);
        return;
    }

    PJ_LOG(3, (THIS_FILE, "Dialing upstream destination: %s", clean_dest));
    pjsua_call_answer(call_id, 180, NULL, NULL);

    pjsua_call_setting call_opt;
    pjsua_call_setting_default(&call_opt);
    call_opt.aud_cnt = 1;
    call_opt.vid_cnt = 0;

    pjsua_msg_data msg_data;
    pjsua_msg_data_init(&msg_data);

    pj_pool_t *inv_pool = pjsua_pool_create("inv_hdrs", 1024, 1024);
    if (inv_pool) {
        pj_str_t pani_name = pj_str("P-Access-Network-Info");
        pj_str_t pani_val  = pj_str("IEEE-802.11");
        pjsip_generic_string_hdr *pani_hdr =
            pjsip_generic_string_hdr_create(inv_pool, &pani_name, &pani_val);
        if (pani_hdr) pj_list_push_back(&msg_data.hdr_list, (pjsip_hdr *)pani_hdr);

        char ppi_buf[256];
        const char *pub_id_raw = getenv("PUBLIC_ID");
        const char *pid = (pub_id_raw && *pub_id_raw) ? pub_id_raw : "sip:+916513585849@br.wln.ims.jio.com";
        if (pid[0] != '<') {
            snprintf(ppi_buf, sizeof(ppi_buf), "<%s>", pid);
        } else {
            snprintf(ppi_buf, sizeof(ppi_buf), "%s", pid);
        }
        pj_str_t ppi_name = pj_str("P-Preferred-Identity");
        pj_str_t ppi_val  = pj_str(ppi_buf);
        pjsip_generic_string_hdr *ppi_hdr =
            pjsip_generic_string_hdr_create(inv_pool, &ppi_name, &ppi_val);
        if (ppi_hdr) pj_list_push_back(&msg_data.hdr_list, (pjsip_hdr *)ppi_hdr);
    }

    pj_str_t dial_uri = pj_str(clean_dest);
    pjsua_call_id out_id;

    pj_status_t status = pjsua_call_make_call(target_acc, &dial_uri,
                                              &call_opt, NULL, &msg_data, &out_id);
    if (status != PJ_SUCCESS && target_acc != g_loc_acc_id) {
        PJ_LOG(2, (THIS_FILE, "target_acc failed (status=%d), trying fallback g_loc_acc_id...", status));
        status = pjsua_call_make_call(g_loc_acc_id, &dial_uri,
                                      &call_opt, NULL, NULL, &out_id);
    }
    if (status != PJ_SUCCESS) {
        PJ_LOG(1, (THIS_FILE, "Failed to dial upstream %s (status=%d)", clean_dest, status));
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

static void on_reg_state(pjsua_acc_id acc_id) {
    pjsua_acc_info ai;
    pjsua_acc_get_info(acc_id, &ai);

    PJ_LOG(3, (THIS_FILE, "Account %d reg status: %d (%.*s)",
               acc_id, ai.status,
               (int)ai.status_text.slen, ai.status_text.ptr));

    if (ai.status == 200) {
        printf("\n===================================================\n");
        printf("[b2bua] SUCCESS: Registered with Jio IMS!\n");
        printf("===================================================\n\n");
    } else if (ai.status == 403) {
        printf("\n===================================================\n");
        printf("[b2bua] ERROR 403: Device Not Whitelisted / Credentials Expired.\n");
        printf("[b2bua] Triggering OTP re-authentication flow...\n");
        printf("===================================================\n\n");
        trigger_otp_flow();
        load_env_file(".env");
        pjsua_acc_set_registration(acc_id, PJ_TRUE);
    } else if (ai.status == 401) {
        printf("[b2bua] Notice 401: Challenge received, sending MD5 credentials...\n");
    }
}

static void set_codecs(void) {
    const pj_str_t keep_amrwb = pj_str("AMR-WB");
    const pj_str_t keep_amr   = pj_str("AMR");
    const pj_str_t keep_pcmu  = pj_str("PCMU");
    const pj_str_t keep_pcma  = pj_str("PCMA");
    
    pjsua_codec_info c[64];
    unsigned n = PJ_ARRAY_SIZE(c);
    
    if (pjsua_enum_codecs(c, &n) != PJ_SUCCESS) return;
    
    for (unsigned i = 0; i < n; i++) {
        if (pj_strstr(&c[i].codec_id, &keep_amrwb))
            pjsua_codec_set_priority(&c[i].codec_id, 255);
        else if (pj_strstr(&c[i].codec_id, &keep_amr))
            pjsua_codec_set_priority(&c[i].codec_id, 254);
        else if (pj_strstr(&c[i].codec_id, &keep_pcmu))
            pjsua_codec_set_priority(&c[i].codec_id, 250);
        else if (pj_strstr(&c[i].codec_id, &keep_pcma))
            pjsua_codec_set_priority(&c[i].codec_id, 248);
        else
            pjsua_codec_set_priority(&c[i].codec_id, 0);
    }
}

/* ------------------------------------------------------------------ */
/* Main                                                               */
/* ------------------------------------------------------------------ */

int main(int argc, char *argv[]) {
    pj_status_t status;

    PJ_UNUSED_ARG(argc);
    PJ_UNUSED_ARG(argv);

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    ensure_env_configured();

    for (int i = 0; i < MAX_CALLS; i++) g_peer_map[i] = PJSUA_INVALID_ID;

    status = pjsua_create();
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

    const char *dns_servers = get_env_def("DNS_SERVERS", "192.168.29.1");
    if (dns_servers && *dns_servers) {
        cfg.nameserver_count = 1;
        cfg.nameserver[0] = pj_str((char *)dns_servers);
    }

    const char *user_agent = get_env_def("USER_AGENT", "JUICEJFV-1.3.32");
    cfg.user_agent = pj_str((char *)user_agent);

    pjsua_logging_config_default(&log_cfg);
    log_cfg.level = atoi(get_env_def("LOG_LEVEL", "4"));

    pjsua_media_config_default(&media_cfg);
    media_cfg.clock_rate = 8000;
    media_cfg.audio_frame_ptime = 20;
    media_cfg.no_vad = PJ_TRUE;

    status = pjsua_init(&cfg, &log_cfg, &media_cfg);
    if (status != PJ_SUCCESS) {
        pjsua_destroy();
        return 1;
    }

    /* UDP Transport (Local softphones) */
    pjsua_transport_config udp_cfg;
    pjsua_transport_config_default(&udp_cfg);
    udp_cfg.port = atoi(get_env_def("LOCAL_PORT", "5061"));

    status = pjsua_transport_create(PJSIP_TRANSPORT_UDP, &udp_cfg, &g_udp_tid);
    if (status != PJ_SUCCESS) {
        pjsua_destroy();
        return 1;
    }

    /* TLS Transport (Jio Router Upstream) */
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

    /* Local Listener Account */
    pjsua_acc_config loc_acc_cfg;
    pjsua_acc_config_default(&loc_acc_cfg);
    loc_acc_cfg.id = pj_str("sip:b2bua@0.0.0.0");
    loc_acc_cfg.register_on_acc_add = PJ_FALSE;
    loc_acc_cfg.transport_id = g_udp_tid; 
    status = pjsua_acc_add(&loc_acc_cfg, PJ_TRUE, &g_loc_acc_id);
    if (status != PJ_SUCCESS) {
        PJ_LOG(1, (THIS_FILE, "Error adding local account"));
        pjsua_destroy();
        return 1;
    }

    /* Upstream Jio IMS Account */
    pjsua_acc_config up_acc_cfg;
    pjsua_acc_config_default(&up_acc_cfg);
    up_acc_cfg.transport_id = g_tls_tid; 

    const char *pub_id_raw  = getenv("PUBLIC_ID");
    const char *proxy_host = getenv("PROXY_HOST");
    const char *proxy_port = get_env_def("PROXY_PORT", "5068");
    const char *realm      = get_env_def("UP_REALM",
                                          get_env_def("SIP_REALM", "br.wln.ims.jio.com"));

    char clean_pub_id[256];
    if (pub_id_raw && *pub_id_raw) {
        sanitize_sip_uri(clean_pub_id, sizeof(clean_pub_id), pub_id_raw);
    } else {
        snprintf(clean_pub_id, sizeof(clean_pub_id), "sip:+916513585849@br.wln.ims.jio.com");
    }

    char default_reg_uri[256], default_proxy_uri[256];
    snprintf(default_reg_uri, sizeof(default_reg_uri), "sip:%s", (realm && *realm && strcmp(realm, "*") != 0) ? realm : "br.wln.ims.jio.com");
    snprintf(default_proxy_uri, sizeof(default_proxy_uri), "sip:%s:%s;transport=tls;lr", (proxy_host && *proxy_host) ? proxy_host : "192.168.29.1", proxy_port);

    const char *up_reg_raw   = get_env_def("UP_REG_URI", default_reg_uri);
    const char *up_proxy_raw = get_env_def("UP_PROXY", default_proxy_uri);
    const char *auth_user    = get_env_def("UP_AUTH_USER", get_env_def("SIP_AUTH_USER", ""));
    const char *auth_pass    = get_env_def("UP_AUTH_PASS", get_env_def("SIP_PASSWORD", ""));

    char clean_up_reg[256], clean_up_proxy[256];
    sanitize_sip_uri(clean_up_reg, sizeof(clean_up_reg), up_reg_raw);
    sanitize_sip_uri(clean_up_proxy, sizeof(clean_up_proxy), up_proxy_raw);

    up_acc_cfg.id = pj_str(clean_pub_id);
    up_acc_cfg.reg_uri = pj_str(clean_up_reg);
    up_acc_cfg.register_on_acc_add = PJ_TRUE;
    up_acc_cfg.reg_timeout = atoi(get_env_def("UP_REG_EXPIRES", "86400"));

    /* Proxy routing to router IP via TLS */
    if (clean_up_proxy[0]) {
        up_acc_cfg.proxy_cnt = 1;
        up_acc_cfg.proxy[0] = pj_str(clean_up_proxy);
    }

    const char *uuid_val = get_env_def("UUID", "00000000-0000-1000-8000-00001CDC13C6");
    char clean_uuid[256];
    sanitize_sip_uri(clean_uuid, sizeof(clean_uuid), uuid_val);
    const char *bare_uuid = clean_uuid;
    if (strncmp(bare_uuid, "urn:uuid:", 9) == 0) {
        bare_uuid += 9;
    }
    
    up_acc_cfg.use_rfc5626 = PJ_FALSE;

    char contact_p[256];
    if (strncmp(bare_uuid, "urn:uuid:", 9) == 0) {
        snprintf(contact_p, sizeof(contact_p), ";+sip.instance=\"<%s>\"", bare_uuid);
    } else {
        snprintf(contact_p, sizeof(contact_p), ";+sip.instance=\"<urn:uuid:%s>\"", bare_uuid);
    }
    up_acc_cfg.contact_params = pj_str(contact_p);

    char clean_auth_user[256];
    const char *au_ptr = auth_user;
    if (au_ptr && strncmp(au_ptr, "sip:", 4) == 0) au_ptr += 4;
    else if (au_ptr && strncmp(au_ptr, "sips:", 5) == 0) au_ptr += 5;
    snprintf(clean_auth_user, sizeof(clean_auth_user), "%s", au_ptr ? au_ptr : "");

    /* Single Credential matching MicroSIP */
    up_acc_cfg.cred_count = 1;
    up_acc_cfg.cred_info[0].realm     = pj_str("*");
    up_acc_cfg.cred_info[0].scheme    = pj_str("Digest");
    up_acc_cfg.cred_info[0].username  = pj_str(clean_auth_user);
    up_acc_cfg.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    up_acc_cfg.cred_info[0].data      = pj_str((char *)auth_pass);

    /* Restore Custom Jio IMS Headers */
    pj_list_init(&up_acc_cfg.reg_hdr_list);
    pj_pool_t *reg_pool = pjsua_pool_create("reg_hdrs", 1024, 1024);
    if (reg_pool) {
        pj_str_t pani_name = pj_str("P-Access-Network-Info");
        pj_str_t pani_val  = pj_str("IEEE-802.11");
        pjsip_generic_string_hdr *pani_hdr =
            pjsip_generic_string_hdr_create(reg_pool, &pani_name, &pani_val);
        if (pani_hdr)
            pj_list_push_back(&up_acc_cfg.reg_hdr_list, (pjsip_hdr *)pani_hdr);

        char ppi_buf[256];
        if (clean_pub_id[0] != '<') {
            snprintf(ppi_buf, sizeof(ppi_buf), "<%s>", clean_pub_id);
        } else {
            snprintf(ppi_buf, sizeof(ppi_buf), "%s", clean_pub_id);
        }
        pj_str_t ppi_name = pj_str("P-Preferred-Identity");
        pj_str_t ppi_val  = pj_str(ppi_buf);
        pjsip_generic_string_hdr *ppi_hdr =
            pjsip_generic_string_hdr_create(reg_pool, &ppi_name, &ppi_val);
        if (ppi_hdr)
            pj_list_push_back(&up_acc_cfg.reg_hdr_list, (pjsip_hdr *)ppi_hdr);
    }

    status = pjsua_acc_add(&up_acc_cfg, PJ_TRUE, &g_up_acc_id);

    if (reg_pool) pj_pool_release(reg_pool);

    if (status != PJ_SUCCESS) {
        PJ_LOG(1, (THIS_FILE, "Error adding upstream account"));
        pjsua_destroy();
        return 1;
    }

    printf("\n[b2bua] B2BUA running. Local UDP:%s  Upstream TLS:%s  DNS:%s  Press Ctrl+C to stop.\n",
           get_env_def("LOCAL_PORT","5061"), get_env_def("TLS_PORT","5068"), dns_servers);

    while (g_running) {
        pjsua_handle_events(100);
    }

    printf("\n[b2bua] Shutting down...\n");

    for (int i = 0; i < MAX_CALLS; i++) {
        if (g_peer_map[i] != PJSUA_INVALID_ID) {
            pjsua_call_hangup(i, 0, NULL, NULL);
        }
    }
    pjsua_handle_events(500);

    pjsua_destroy();
    return 0;
}