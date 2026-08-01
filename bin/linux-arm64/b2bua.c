/*
 * b2bua.c - JioFiber SIP Back-to-Back User Agent (PJSIP / PJSUA 2.x)
 * Fixed for TLS, bypass verification, and proper signal handling.
 */

#include <pjsua-lib/pjsua.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <signal.h>

#define THIS_FILE "b2bua.c"

static pjsua_acc_id g_loc_acc_id = PJSUA_INVALID_ID;
static pjsua_acc_id g_up_acc_id = PJSUA_INVALID_ID;
static pj_bool_t g_running = PJ_TRUE;

/* Signal handler for graceful exit on Ctrl+C */
static void signal_handler(int sig) {
    PJ_UNUSED_ARG(sig);
    g_running = PJ_FALSE;
}

/* Trim whitespace from string */
static char *trim_str(char *str) {
    char *end;
    while (isspace((unsigned char)*str)) str++;
    if (*str == 0) return str;
    end = str + strlen(str) - 1;
    while (end > str && isspace((unsigned char)*end)) end--;
    end[1] = '\0';
    return str;
}

/* Load .env file into process environment */
static void load_env_file(const char *filename) {
    FILE *f = fopen(filename, "r");
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
        if (vlen >= 2 && ((val[0] == '"' && val[vlen-1] == '"') || (val[0] == '\'' && val[vlen-1] == '\''))) {
            val[vlen-1] = '\0';
            val++;
        }

        if (*key && *val) {
#ifdef _WIN32
            char envbuf[512];
            snprintf(envbuf, sizeof(envbuf), "%s=%s", key, val);
            _putenv(envbuf);
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

static void on_incoming_call(pjsua_acc_id acc_id, pjsua_call_id call_id, pjsip_rx_data *rdata) {
    pjsua_call_info ci;
    PJ_UNUSED_ARG(rdata);

    pjsua_call_get_info(call_id, &ci);
    PJ_LOG(3, (THIS_FILE, "Incoming call %d from %.*s (account %d)", 
               call_id, (int)ci.remote_info.slen, ci.remote_info.ptr, acc_id));

    pjsua_call_setting call_opt;
    pjsua_call_setting_default(&call_opt);
    call_opt.aud_cnt = 1;
    call_opt.vid_cnt = 0;

    pjsua_call_answer(call_id, 200, NULL, NULL);
}

static void on_call_state(pjsua_call_id call_id, pjsip_event *e) {
    pjsua_call_info ci;
    PJ_UNUSED_ARG(e);

    pjsua_call_get_info(call_id, &ci);
    PJ_LOG(3, (THIS_FILE, "Call %d state changed to %s", 
               call_id, ci.state_text.ptr));

    if (ci.state == PJSIP_INV_STATE_DISCONNECTED) {
        PJ_LOG(3, (THIS_FILE, "Call %d disconnected (reason: %.*s)", 
                   call_id, (int)ci.last_status_text.slen, ci.last_status_text.ptr));
    }
}

static void on_reg_state(pjsua_acc_id acc_id) {
    pjsua_acc_info ai;
    pjsua_acc_get_info(acc_id, &ai);

    PJ_LOG(3, (THIS_FILE, "Account %d reg status: %d (%.*s)", 
               acc_id, ai.status, (int)ai.status_text.slen, ai.status_text.ptr));
}

int main(int argc, char *argv[]) {
    pj_status_t status;

    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    load_env_file(".env");

    status = pjsua_create();
    if (status != PJ_SUCCESS) return 1;

    pjsua_config cfg;
    pjsua_logging_config log_cfg;
    pjsua_media_config media_cfg;

    pjsua_config_default(&cfg);
    cfg.cb.on_incoming_call = &on_incoming_call;
    cfg.cb.on_call_state = &on_call_state;
    cfg.cb.on_reg_state = &on_reg_state;

    const char *user_agent = get_env_def("USER_AGENT", "AnkurProxy/1.0");
    cfg.user_agent = pj_str((char *)user_agent);

    pjsua_logging_config_default(&log_cfg);
    log_cfg.level = atoi(get_env_def("LOG_LEVEL", "4"));

    pjsua_media_config_default(&media_cfg);

    status = pjsua_init(&cfg, &log_cfg, &media_cfg);
    if (status != PJ_SUCCESS) {
        pjsua_destroy();
        return 1;
    }

    /* UDP Transport (Local softphones) */
    pjsua_transport_config udp_cfg;
    pjsua_transport_config_default(&udp_cfg);
    udp_cfg.port = atoi(get_env_def("LOCAL_PORT", "5061"));

    pjsua_transport_id udp_id;
    status = pjsua_transport_create(PJSIP_TRANSPORT_UDP, &udp_cfg, &udp_id);
    if (status != PJ_SUCCESS) {
        pjsua_destroy();
        return 1;
    }

    /* TLS Transport (Jio Router Upstream) */
    pjsua_transport_config tls_cfg;
    pjsua_transport_config_default(&tls_cfg);
    tls_cfg.port = atoi(get_env_def("TLS_PORT", "5068"));
    
    /* FIX: Disable TLS verification for Jio Router self-signed certs */
    tls_cfg.tls_setting.method = PJSIP_SSL_DEFAULT_METHOD;
    tls_cfg.tls_setting.verify_server = PJ_FALSE;
    tls_cfg.tls_setting.verify_client = PJ_FALSE;

    pjsua_transport_id tls_id;
    status = pjsua_transport_create(PJSIP_TRANSPORT_TLS, &tls_cfg, &tls_id);
    if (status != PJ_SUCCESS) {
        PJ_LOG(1, (THIS_FILE, "Error creating SIP TLS transport (status=%d)", status));
    }

    status = pjsua_start();
    if (status != PJ_SUCCESS) {
        pjsua_destroy();
        return 1;
    }

    /* Local Listener Account */
    pjsua_acc_config loc_acc_cfg;
    pjsua_acc_config_default(&loc_acc_cfg);
    loc_acc_cfg.id = pj_str((char *)get_env_def("LOC_ID_URI", "sip:b2bua@0.0.0.0"));
    loc_acc_cfg.register_on_acc_add = PJ_FALSE;
    pjsua_acc_add(&loc_acc_cfg, PJ_TRUE, &g_loc_acc_id);

    /* Upstream Jio IMS Account */
    pjsua_acc_config up_acc_cfg;
    pjsua_acc_config_default(&up_acc_cfg);

    const char *pub_id = getenv("PUBLIC_ID");
    const char *realm_env = getenv("SIP_REALM");
    const char *reg_host = getenv("REGISTRAR_HOST");
    const char *reg_port = get_env_def("REGISTRAR_PORT", "5068");
    const char *proxy_host = getenv("PROXY_HOST");
    const char *proxy_port = get_env_def("PROXY_PORT", "5068");

    char default_id_uri[256], default_reg_uri[256], default_proxy_uri[256];

    snprintf(default_id_uri, sizeof(default_id_uri), "%s", (pub_id && *pub_id) ? pub_id : "sip:user@ue.wln.ims.jio.com");
    snprintf(default_reg_uri, sizeof(default_reg_uri), "sip:%s:%s;transport=tls", (reg_host && *reg_host) ? reg_host : "192.168.29.1", reg_port);
    snprintf(default_proxy_uri, sizeof(default_proxy_uri), "sip:%s:%s;transport=tls", (proxy_host && *proxy_host) ? proxy_host : "192.168.29.1", proxy_port);

    const char *up_id = get_env_def("UP_ID_URI", default_id_uri);
    const char *up_reg = get_env_def("UP_REG_URI", default_reg_uri);
    const char *up_proxy = get_env_def("UP_PROXY", default_proxy_uri);
    const char *auth_user = get_env_def("UP_AUTH_USER", get_env_def("SIP_AUTH_USER", ""));
    const char *auth_pass = get_env_def("UP_AUTH_PASS", get_env_def("SIP_PASSWORD", ""));
    const char *realm = get_env_def("UP_REALM", get_env_def("SIP_REALM", "ue.wln.ims.jio.com"));

    up_acc_cfg.id = pj_str((char *)up_id);
    up_acc_cfg.reg_uri = pj_str((char *)up_reg);
    up_acc_cfg.register_on_acc_add = PJ_TRUE;

    if (*up_proxy) {
        up_acc_cfg.proxy_cnt = 1;
        up_acc_cfg.proxy[0] = pj_str((char *)up_proxy);
    }

    const char *uuid_val = get_env_def("UUID", "<urn:uuid:00000000-0000-1000-8000-0000203D3014>");
    up_acc_cfg.rfc5626_instance_id = pj_str((char *)uuid_val);

    up_acc_cfg.cred_count = 1;
    up_acc_cfg.cred_info[0].realm = pj_str((char *)realm);
    up_acc_cfg.cred_info[0].scheme = pj_str("digest");
    up_acc_cfg.cred_info[0].username = pj_str((char *)auth_user);
    up_acc_cfg.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    up_acc_cfg.cred_info[0].data = pj_str((char *)auth_pass);

    pjsua_acc_add(&up_acc_cfg, PJ_TRUE, &g_up_acc_id);

    printf("\n[b2bua] Proxy running. Press Ctrl+C to stop.\n");

    while (g_running) {
        pjsua_handle_events(100);
    }

    printf("\n[b2bua] Shutting down...\n");
    pjsua_destroy();
    return 0;
}