#!/usr/bin/env python3
"""
build_riscv64.py - Single-command cross-compiler for Linux RISC-V 64-bit (riscv64)
Cross-compiles PJSIP 2.15.1 source + src/b2bua.cpp into a standalone RISC-V 64-bit binary.
"""

import os
import sys
import subprocess
import shutil
from concurrent.futures import ThreadPoolExecutor

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pj_dir = os.path.join(root, 'third_party', 'pjproject-2.15.1')
obj_dir = os.path.join(root, 'riscv64_objs')
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
    '/tmp/riscv64_sysroot/usr/include',
    '/tmp/riscv64_sysroot/usr/include/riscv64-linux-gnu',
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
    'ioqueue_select.c', 'ioqueue_dummy.c', 'ioqueue_common_abs.c', 'ioqueue_kqueue.c',
    'os_core_win32.c', 'os_timestamp_win32.c', 'os_error_win32.c', 'guid_win32.c',
    'ip_helper_winphone8.c', 'ip_helper_win32.c', 'os_time_bsd.c', 'os_time_darwin.c',
    'os_core_bsd.c', 'os_core_darwin.c', 'os_core_rtems.c', 'os_core_symbian.c', 'os_core_vxworks.c',
    'guid_android.c', 'guid_darwin.c', 'guid_bsd.c', 'guid_uuid.c',
    'extra-exports.c', 'log_writer_printk.c', 'pool_policy_kmalloc.c', 'sock_qos_wm.c',
    'ssl_sock_imp_common.c', 'unittest.c', 'transport_srtp_sdes.c', 'transport_srtp_dtls.c', 'libresample_dll.c'
}

exclude_prefixes = ['test_', 'sample_']

b2bua_src = os.path.join(root, 'src', 'b2bua.cpp')

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
defs = '-DPJ_LINUX=1 -DPJ_HAS_IPV6=1 -D_GNU_SOURCE -DPJ_IS_LITTLE_ENDIAN=1 -DPJ_IS_BIG_ENDIAN=0 -DPJ_M_RISCV64=1 -DPJ_HAS_NETINET_TCP_H=1 -DPJ_HAS_LIMITS_H=1 -DPJ_SOCK_HAS_INET_PTON=1 -DPJ_SOCK_HAS_INET_NTOP=1 -DPJ_SOCK_HAS_INET_ATON=1 -DPJMEDIA_AUDIO_DEV_HAS_NULL_AUDIO=1 -DPJMEDIA_AUDIO_DEV_HAS_WMME=0 -DPJMEDIA_AUDIO_DEV_HAS_ALSA=0 -DPJMEDIA_AUDIO_DEV_HAS_PORTAUDIO=0 -DPJSIP_MAX_URL_SIZE=1024 -DPJMEDIA_HAS_OPENCORE_AMRNB_CODEC=0 -DPJMEDIA_HAS_G711_CODEC=1 -DPJMEDIA_HAS_G722_CODEC=1 -DPJMEDIA_HAS_GSM_CODEC=1'

failed_files = []

def compile_file(item):
    i, src = item
    base_name = os.path.basename(src).replace('.cpp', '.o').replace('.c', '.o')
    obj_path = os.path.join(obj_dir, f"{i}_{base_name}")
    compiler = "riscv64-linux-gnu-g++" if src.endswith('.cpp') else "riscv64-linux-gnu-gcc"
    std_flag = "-std=c++17" if src.endswith('.cpp') else ""
    cmd = f'{compiler} -c -O2 {std_flag} {defs} {inc_cmd} "{src}" -o "{obj_path}"'
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        failed_files.append((src, res.stderr.strip()))
        return None
    return obj_path

print(f"Compiling {len(c_files)} files with RISC-V 64 Cross Compiler (riscv64-linux-gnu-g++) in parallel...")
with ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(compile_file, enumerate(c_files)))

if failed_files:
    print(f"\n{len(failed_files)} files failed to compile:")
    for f, err in failed_files:
        print(f"  FAIL: {os.path.basename(f)}:\n{err}\n")
    sys.exit(1)

valid_objs = [os.path.normpath(o) for o in results if o and os.path.exists(o)]
print(f"Successfully compiled {len(valid_objs)} / {len(c_files)} RISC-V 64 object files.")

output_dir = os.path.join(root, 'bin', 'linux-riscv64')
os.makedirs(output_dir, exist_ok=True)
out_exe = os.path.join(output_dir, 'b2bua')

print("\nLinking native Linux RISC-V 64 executable b2bua...")
objs_str = " ".join([f'"{o}"' for o in valid_objs])

lib_search = [
    '/tmp/riscv64_sysroot/usr/lib/riscv64-linux-gnu',
    '/tmp/riscv64_sysroot/usr/lib',
    '/tmp/riscv64_sysroot/lib/riscv64-linux-gnu',
    '/tmp/riscv64_sysroot/lib',
    '/usr/lib/riscv64-linux-gnu',
    '/usr/riscv64-linux-gnu/lib'
]
lib_flags = " ".join([f"-L{p}" for p in lib_search if os.path.exists(p)])
link_cmd = f'riscv64-linux-gnu-g++ {objs_str} -o "{out_exe}" {lib_flags} -lssl -lcrypto -lpthread -lm -ldl'

res = subprocess.run(link_cmd, shell=True, capture_output=True, text=True)
if res.returncode != 0:
    print(f"[!] Linking failed:\n{res.stderr}")
    sys.exit(1)

size = os.path.getsize(out_exe)
print(f"\n=== SUCCESS! ===")
print(f"bin/linux-riscv64/b2bua ({size:,} bytes / {size // 1024} KB)")
