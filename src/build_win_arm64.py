#!/usr/bin/env python3
"""
build_win_arm64.py - Single-command cross-compiler for Windows on ARM64 (win-arm64)
Compiles PJSIP 2.15.1 source + src/b2bua.cpp into a native Windows ARM64 executable using MSVC.
"""

import os
import sys
import subprocess
import shutil
from concurrent.futures import ThreadPoolExecutor

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pj_dir = os.path.join(root, 'third_party', 'pjproject-2.15.1')
obj_dir = os.path.join(root, 'win_arm64_objs')
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
    'os_core_unix.c', 'os_time_unix.c', 'os_core_bsd.c', 'os_core_darwin.c',
    'os_core_rtems.c', 'os_core_symbian.c', 'os_core_vxworks.c',
    'guid_android.c', 'guid_darwin.c', 'guid_bsd.c'
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
                if fname in exact_excludes or any(fname.startswith(k) for k in exclude_prefixes):
                    continue
                c_files.append(os.path.join(dpath, f))

inc_cmd = " ".join([f'/I"{d}"' for d in inc_dirs])
defs = '/D_WIN32_WINNT=0x0601 /DWIN32 /D_WINDOWS /DPJ_WIN32=1 /DPJ_M_ARM64=1 /DUNICODE /D_UNICODE /DPJMEDIA_AUDIO_DEV_HAS_WMME=1 /DPJMEDIA_AUDIO_DEV_HAS_NULL_AUDIO=1 /DPJSIP_MAX_URL_SIZE=1024 /DPJMEDIA_HAS_OPENCORE_AMRNB_CODEC=0 /DPJMEDIA_HAS_G711_CODEC=1 /DPJMEDIA_HAS_G722_CODEC=1 /DPJMEDIA_HAS_GSM_CODEC=1'

failed_files = []

def compile_file(item):
    i, src = item
    base_name = os.path.basename(src).replace('.cpp', '.obj').replace('.c', '.obj')
    obj_path = os.path.join(obj_dir, f"{i}_{base_name}")
    std_flag = "/std:c++17" if src.endswith('.cpp') else ""
    cmd = f'cl.exe /c /O2 /MD /EHsc {std_flag} {defs} {inc_cmd} "{src}" /Fo"{obj_path}"'
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        failed_files.append((src, res.stderr[:200]))
        return None
    return obj_path

print(f"Compiling {len(c_files)} files with MSVC cl.exe (ARM64) in parallel...")
with ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(compile_file, enumerate(c_files)))

if failed_files:
    print(f"\n{len(failed_files)} files failed to compile:")
    for f, err in failed_files:
        print(f"  FAIL: {os.path.basename(f)}: {err.strip().replace(chr(10), ' ')}")

valid_objs = [os.path.normpath(o) for o in results if o and os.path.exists(o)]
print(f"Successfully compiled {len(valid_objs)} / {len(c_files)} MSVC ARM64 object files.")

output_dir = os.path.join(root, 'bin', 'windows-arm64')
os.makedirs(output_dir, exist_ok=True)
out_exe = os.path.join(output_dir, 'b2bua_win_arm64.exe')

print("\nLinking native Windows ARM64 executable b2bua_win_arm64.exe...")
objs_str = " ".join([f'"{o}"' for o in valid_objs])
link_cmd = f'link.exe /MACHINE:ARM64 {objs_str} /OUT:"{out_exe}" ws2_32.lib winmm.lib winhttp.lib ole32.lib advapi32.lib user32.lib iphlpapi.lib'

res = subprocess.run(link_cmd, shell=True, capture_output=True, text=True)
if res.returncode != 0:
    print(f"[!] Linking failed:\n{res.stderr}")
    sys.exit(1)

size = os.path.getsize(out_exe)
print(f"\n=== SUCCESS! ===")
print(f"bin/windows-arm64/b2bua_win_arm64.exe ({size:,} bytes / {size // 1024} KB)")
