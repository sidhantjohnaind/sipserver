#!/usr/bin/env python3
"""
build_mingw.py - Cross-compiles PJSIP + src/b2bua.cpp for Windows x64 using MinGW-w64
Outputs a 100% standalone, statically-linked Windows executable with Dual SCM Service + Console mode.
"""

import os
import sys
import subprocess
import shutil
from concurrent.futures import ThreadPoolExecutor

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pj_dir = os.path.join(root, 'third_party', 'pjproject-2.15.1')
obj_dir = os.path.join(root, 'mingw_objs')
if os.path.exists(obj_dir):
    shutil.rmtree(obj_dir)
os.makedirs(obj_dir, exist_ok=True)

ssl_dir = '/tmp/mingw64_ssl'
inc_dirs = [
    pj_dir,
    os.path.join(pj_dir, 'pjlib', 'include'),
    os.path.join(pj_dir, 'pjlib-util', 'include'),
    os.path.join(pj_dir, 'pjnath', 'include'),
    os.path.join(pj_dir, 'pjmedia', 'include'),
    os.path.join(pj_dir, 'pjsip', 'include'),
    os.path.join(pj_dir, 'third_party', 'resample', 'include'),
    os.path.join(ssl_dir, 'include'),
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
    'main.c', 'milenage.c', 'speex_codec.c',
    'file_access_unistd.c', 'file_io_ansi.c', 'guid_simple.c',
    'ioqueue_select.c', 'ioqueue_kqueue.c', 'ioqueue_epoll.c',
    'os_time_bsd.c', 'os_time_darwin.c', 'os_time_unix.c',
    'os_timestamp_posix.c', 'os_error_unix.c', 'os_core_unix.c',
    'ip_helper_generic.c', 'ip_helper_winphone8.c',
    'sock_qos_bsd.c', 'sock_qos_darwin.c', 'sock_qos_wm.c',
    'ssl_sock_gtls.c', 'ssl_sock_darwin.c', 'ssl_sock_schannel.c', 'ssl_sock_imp_common.c',
    'extra-exports.c', 'unittest.c', 'transport_srtp_sdes.c', 'transport_srtp_dtls.c',
    'libresample_dll.c', 'os_core_bsd.c', 'os_core_darwin.c', 'os_core_rtems.c',
    'os_core_symbian.c', 'os_core_vxworks.c', 'guid_android.c', 'guid_darwin.c',
    'guid_bsd.c', 'guid_uuid.c', 'log_writer_printk.c', 'pool_policy_kmalloc.c',
    'os_rwmutex.c', 'b2bua.c', 'pjlib_test.c', 'g7221.c', 'g7221_test.c',
    'ipp_sample.c', 'silkg7221.c', 'sbc.c', 'plc_test.c', 'resample_test.c',
    'rtpdump.c', 'sdp_test.c', 'sip_rtp_test.c', 'sound_test.c', 'tonegen_test.c', 'vid_port_test.c'
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
                if fname.endswith('_directx.c') or fname.endswith('_wince.c') or fname.endswith('_linux.c'):
                    continue
                if fname in exact_excludes or any(fname.startswith(k) for k in exclude_prefixes):
                    continue
                c_files.append(os.path.join(dpath, f))

inc_cmd = " ".join([f'-I"{d}"' for d in inc_dirs])
defs = '-DPJ_WIN32=1 -DPJ_M_X86_64=1 -D_WIN32_WINNT=0x0601 -DWINVER=0x0601 -DPJ_HAS_IPV6=1 -DPJ_IS_LITTLE_ENDIAN=1 -DPJ_IS_BIG_ENDIAN=0 -DPJMEDIA_AUDIO_DEV_HAS_NULL_AUDIO=1 -DPJMEDIA_AUDIO_DEV_HAS_WMME=0 -DPJMEDIA_AUDIO_DEV_HAS_ALSA=0 -DPJMEDIA_AUDIO_DEV_HAS_PORTAUDIO=0 -DPJSIP_MAX_URL_SIZE=1024 -DPJMEDIA_HAS_OPENCORE_AMRNB_CODEC=0 -DPJMEDIA_HAS_G711_CODEC=1 -DPJMEDIA_HAS_G722_CODEC=1 -DPJMEDIA_HAS_GSM_CODEC=1'

failed_files = []

def compile_file(item):
    i, src = item
    base_name = os.path.basename(src).replace('.cpp', '.o').replace('.c', '.o')
    obj_path = os.path.join(obj_dir, f"{i}_{base_name}")
    compiler = "x86_64-w64-mingw32-g++" if src.endswith('.cpp') else "x86_64-w64-mingw32-gcc"
    std_flag = "-std=c++17" if src.endswith('.cpp') else ""
    cmd = f'{compiler} -c -O2 {std_flag} {defs} {inc_cmd} "{src}" -o "{obj_path}"'
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        failed_files.append((src, res.stderr[:200]))
        return None
    return obj_path

print(f"Compiling {len(c_files)} files with MinGW-w64 (x86_64-w64-mingw32-g++) in parallel...")
with ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(compile_file, enumerate(c_files)))

if failed_files:
    print(f"\n{len(failed_files)} files failed to compile:")
    for f, err in failed_files:
        print(f"  FAIL: {os.path.basename(f)}: {err.strip().replace(chr(10), ' ')}")

valid_objs = [os.path.normpath(o) for o in results if o and os.path.exists(o)]
print(f"Successfully compiled {len(valid_objs)} / {len(c_files)} Windows object files.")

out_bin = os.path.join(root, 'b2bua_msvc.exe')
win_lib_dir = os.path.join(ssl_dir, 'lib')
if not os.path.exists(win_lib_dir):
    win_lib_dir = os.path.join(ssl_dir, 'lib64')

link_cmd = f'x86_64-w64-mingw32-g++ -o "{out_bin}" {" ".join([f"{vo}" for vo in valid_objs])} -L"{win_lib_dir}" -lssl -lcrypto -lws2_32 -lmswsock -lwinhttp -liphlpapi -ladvapi32 -lcrypt32 -lole32 -loleaut32 -luuid -luser32 -static'

print("\nLinking native Windows x64 executable b2bua_msvc.exe...")
res = subprocess.run(link_cmd, shell=True, capture_output=True, text=True)

if os.path.exists(out_bin):
    sz = os.path.getsize(out_bin)
    print(f"\n=== SUCCESS! ===")
    print(f"b2bua_msvc.exe ({sz:,} bytes / {sz/1024:.0f} KB)")
    os.makedirs(os.path.join(root, 'bin', 'windows-x64'), exist_ok=True)
    shutil.copy2(out_bin, os.path.join(root, 'bin', 'windows-x64', 'b2bua_msvc.exe'))
    print(f"Copied to bin/windows-x64/b2bua_msvc.exe")
else:
    print(f"\nWindows Link error:\n{res.stderr[:2000]}")
    print(f"Windows Link stdout:\n{res.stdout[:2000]}")
