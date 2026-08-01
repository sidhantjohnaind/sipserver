#!/usr/bin/env python3
"""
Apply JioFiber B2BUA patches to stock PJSIP 2.15.1 source.

Usage:
    python apply_patches.py

Run this ONCE after downloading stock PJSIP 2.15.1 into third_party/pjproject-2.15.1/
"""
import os, sys

root = os.path.dirname(os.path.abspath(__file__))
pjsip_dir = os.path.join(root, "third_party", "pjproject-2.15.1")

if not os.path.isdir(pjsip_dir):
    print(f"ERROR: PJSIP not found at {pjsip_dir}")
    print("Download PJSIP 2.15.1 from https://github.com/pjsip/pjproject/releases/tag/2.15.1")
    print("and extract it to third_party/pjproject-2.15.1/")
    sys.exit(1)

def patch_file(filepath, replacements):
    if not os.path.exists(filepath):
        print(f"  MISSING: {filepath}")
        return False
    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    modified = False
    for target, replacement in replacements:
        if replacement in content:
            print("  ALREADY APPLIED")
            return True
        if target in content:
            content = content.replace(target, replacement, 1)
            modified = True
        else:
            print(f"  TARGET NOT FOUND in {os.path.basename(filepath)}")
            return False

    if modified:
        with open(filepath, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        print("  SUCCESSFULLY APPLIED")
        return True
    return True

print("Applying JioFiber B2BUA patches to PJSIP 2.15.1...")

# 1. opencore_amr.c patch
amr_file = os.path.join(pjsip_dir, "pjmedia", "src", "pjmedia-codec", "opencore_amr.c")
amr_replacements = [
    (
        '#define PJ_TRACE    0',
        '#define PJ_TRACE    1'
    ),
    (
        '#   define TRACE_(expr) PJ_LOG(4,expr)',
        '#   define TRACE_(expr) PJ_LOG(1,expr)'
    ),
    (
        '    PJ_FALSE,       /* octet align      */\n    5900            /* bitrate          */',
        '    PJ_TRUE,        /* octet align (Jio Fiber IMS requires octet-aligned) */\n    12200           /* bitrate (12.20 kbps, Mode 7 - Jio VoLTE standard) */'
    ),
    (
        '    PJ_FALSE,       /* octet align      */\n    12650           /* bitrate          */',
        '    PJ_TRUE,        /* octet align (Jio Fiber IMS requires octet-aligned) */\n    12650           /* bitrate          */'
    ),
    (
        '    attr->setting.vad = 1;',
        '    attr->setting.vad = 0;'
    ),
    (
        '    if (def_config[idx].octet_align) {\n        attr->setting.dec_fmtp.cnt = 1;\n        attr->setting.dec_fmtp.param[0].name = pj_str("octet-align");\n        attr->setting.dec_fmtp.param[0].val = pj_str("1");\n    }',
        '    if (def_config[idx].octet_align) {\n        attr->setting.dec_fmtp.cnt = 2;\n        attr->setting.dec_fmtp.param[0].name = pj_str("octet-align");\n        attr->setting.dec_fmtp.param[0].val = pj_str("1");\n        /* JioFiber JUICE re-INVITEs demand mode-set echoed; advertise all modes */\n        attr->setting.dec_fmtp.param[1].name = pj_str("mode-set");\n        attr->setting.dec_fmtp.param[1].val = (idx==IDX_AMR_NB)?\n            pj_str("0,1,2,3,4,5,6,7") : pj_str("0,1,2,3,4,5,6,7,8");\n    }'
    )
]

print("\n1. Patching opencore_amr.c (octet-align=1, bitrate=12200, mode-set, VAD off):")
ok_amr = patch_file(amr_file, amr_replacements)

# 2. stream.c patch
stream_file = os.path.join(pjsip_dir, "pjmedia", "src", "pjmedia", "stream.c")
stream_replacements = [
    (
        '        /* Get frame from jitter buffer. */\n        pjmedia_jbuf_get_frame2(stream->jb, channel->out_pkt, &frame_size,\n                                &frame_type, &bit_info);',
        '        pjmedia_jbuf_get_frame2(stream->jb, channel->out_pkt, &frame_size,\n                                &frame_type, &bit_info);\n\n        if (frame_type != PJMEDIA_JB_NORMAL_FRAME) {\n            PJ_LOG(1, (THIS_FILE, "JB get_frame stream=%s type=%d size=%d", stream->port.info.name.ptr, frame_type, (int)frame_size));\n        } else {\n            PJ_LOG(1, (THIS_FILE, "JB get_frame stream=%s NORMAL size=%d", stream->port.info.name.ptr, (int)frame_size));\n        }'
    )
]

print("\n2. Patching stream.c (JB frame-type trace logging):")
ok_stream = patch_file(stream_file, stream_replacements)

print("\n" + "="*50)
if ok_amr and ok_stream:
    print("SUCCESS: All PJSIP 2.15.1 patches are verified and ready!")
else:
    print("WARNING: Some patches failed to apply.")
