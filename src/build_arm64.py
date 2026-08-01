#!/usr/bin/env python3
import os
import sys
import subprocess
import shutil
from concurrent.futures import ThreadPoolExecutor

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pj_dir = os.path.join(root, 'third_party', 'pjproject-2.15.1')
obj_dir = os.path.join(root, 'arm64_objs')
if os.path.exists(obj_dir):
    shutil.rmtree(obj_dir)
os.makedirs(obj_dir, exist_ok=True)

inc_dirs = [
    pj_dir,
    os.path.join(pj_dir, 'pjlib', 'include'),
    os.path.join(pj_dir, 'pjlib-util', 'include'),
    os.path.join(pj_dir, 'pjnath', 'include'),
    os.path.join(pj_dir, 'pjmedia', 'include'),
    os.path.join(pj_dir, 'pjsip', 'include'),
    os.path.join(pj_dir, 'third_party', 'resample', 'include'),
    os.path.join(root, 'third_party', 'opencore-amr', 'include'),
    '/usr/include/aarch64-linux-gnu',
]

subdirs = [
    ('pjlib', 'src', 'pj'),
    ('pjlib-util', 'src', 'pjlib-util'),
    ('pjnath', 'src', 'pjnath'),
    ('pjmedia', 'src', 'pjmedia'),
    ('pjmedia', 'src', 'pjmedia-codec'),
    ('pjmedia', 'src', 'pjmedia-audiodev'),
    ('pjsip', 'src', 'pjsip'),
    ('pjsip', 'src', 'pjsip-ua'),
    ('pjsip', 'src', 'pjsip-simple'),
    ('pjsip', 'src', 'pjsua-lib'),
    ('third_party', 'resample', 'src'),
]

exact_excludes = {
    'pjlib_test.c', 'main.c', 'main_mobile.c', 'mips_test.c',
    'g7221.c', 'g7221_test.c', 'ipp_sample.c',
    'silkg7221.c', 'sbc.c', 'plc_test.c', 'resample_test.c',
    'rtpdump.c', 'sdp_test.c', 'sip_rtp_test.c', 'sound_test.c',
    'tonegen_test.c', 'vid_port_test.c', 'b2bua.c', 'b2bua.cpp',
    'ioqueue_select.c', 'ioqueue_dummy.c', 'ioqueue_common_abs.c',
    'os_core_win32.c', 'os_timestamp_win32.c', 'os_error_win32.c', 'guid_win32.c',
    'ip_helper_winphone8.c', 'ip_helper_win32.c', 'os_time_bsd.c', 'os_time_darwin.c',
    'os_core_bsd.c', 'os_core_darwin.c', 'os_core_rtems.c', 'os_core_symbian.c', 'os_core_vxworks.c',
    'guid_android.c', 'guid_darwin.c', 'guid_bsd.c'
}

exclude_prefixes = ['test_', 'sample_']

b2bua_src = os.path.join(root, 'src', 'b2bua.cpp')
if not os.path.exists(b2bua_src):
    b2bua_src = os.path.join(root, 'src', 'b2bua.c')

c_files = [b2bua_src]
for sd in subdirs:
    dpath = os.path.join(pj_dir, *sd)
    if os.path.exists(dpath):
        for f in os.listdir(dpath):
            if f.endswith('.c'):
                fname = f.lower()
                if fname.endswith('_win32.c') or fname.endswith('_win32_directx.c') or fname.endswith('_wince.c'):
                    continue
                if fname in exact_excludes or any(fname.startswith(k) for k in exclude_prefixes):
                    continue
                c_files.append(os.path.join(dpath, f))

inc_cmd = " ".join([f'-I"{d}"' for d in inc_dirs])
defs = '-DPJ_LINUX=1 -DPJ_HAS_IPV6=1 -D_GNU_SOURCE -DPJ_IS_LITTLE_ENDIAN=1 -DPJ_IS_BIG_ENDIAN=0 -DPJ_M_ARM64=1 -DPJ_HAS_NETINET_TCP_H=1 -DPJ_HAS_LIMITS_H=1 -DPJ_SOCK_HAS_INET_PTON=1 -DPJ_SOCK_HAS_INET_NTOP=1 -DPJ_SOCK_HAS_INET_ATON=1 -DPJMEDIA_AUDIO_DEV_HAS_NULL_AUDIO=1 -DPJMEDIA_AUDIO_DEV_HAS_WMME=0 -DPJMEDIA_AUDIO_DEV_HAS_ALSA=0 -DPJMEDIA_AUDIO_DEV_HAS_PORTAUDIO=0 -DPJSIP_MAX_URL_SIZE=1024 -DPJMEDIA_HAS_OPENCORE_AMRNB_CODEC=0 -DPJMEDIA_HAS_G711_CODEC=1 -DPJMEDIA_HAS_G722_CODEC=1 -DPJMEDIA_HAS_GSM_CODEC=1'

failed_files = []

def compile_file(item):
    i, src = item
    base_name = os.path.basename(src).replace('.cpp', '.o').replace('.c', '.o')
    obj_path = os.path.join(obj_dir, f"{i}_{base_name}")
    compiler = "aarch64-linux-gnu-g++" if src.endswith('.cpp') else "aarch64-linux-gnu-gcc"
    std_flag = "-std=c++17" if src.endswith('.cpp') else ""
    cmd = f'{compiler} -c -O2 {std_flag} {defs} {inc_cmd} "{src}" -o "{obj_path}"'
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        failed_files.append((src, res.stderr[:200]))
        return None
    return obj_path

print(f"Compiling {len(c_files)} files with ARM64 Cross Compiler (aarch64-linux-gnu-g++) in parallel...")
with ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(compile_file, enumerate(c_files)))

if failed_files:
    print(f"\n{len(failed_files)} files failed to compile:")
    for f, err in failed_files:
        print(f"  FAIL: {os.path.basename(f)}: {err.strip().replace(chr(10), ' ')}")

valid_objs = [os.path.normpath(o) for o in results if o and os.path.exists(o)]
print(f"Successfully compiled {len(valid_objs)} / {len(c_files)} ARM64 Linux object files.")

obj_str = " ".join([f'"{vo}"' for vo in valid_objs])
out_dir = os.path.join(root, 'bin', 'linux-arm64')
os.makedirs(out_dir, exist_ok=True)
out_bin = os.path.join(out_dir, 'b2bua')
link_cmd = f'aarch64-linux-gnu-g++ -o "{out_bin}" {obj_str} -L/usr/lib/aarch64-linux-gnu -lssl -lcrypto -lpthread -lm'

print("\nLinking native Linux ARM64 executable bin/linux-arm64/b2bua...")
res = subprocess.run(link_cmd, shell=True, capture_output=True, text=True)

if os.path.exists(out_bin):
    sz = os.path.getsize(out_bin)
    print(f"\n=== SUCCESS! ===")
    print(f"bin/linux-arm64/b2bua ({sz:,} bytes / {sz/1024:.0f} KB)")
    print(f"100% native Linux ARM64 executable cross-compiled!")
else:
    print(f"\nLinux ARM64 Link error:\n{res.stderr[:2000]}")
    print(f"Linux ARM64 Link stdout:\n{res.stdout[:2000]}")
