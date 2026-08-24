import os
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor

root = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(root) in ['scripts', 'src', 'bin']:
    root = os.path.dirname(root)

pj_dir = os.path.join(root, 'third_party', 'pjproject-2.15.1')
if not os.path.exists(pj_dir):
    pj_dir = os.path.join(root, 'pjproject-2.15.1')

obj_dir = os.path.join(root, 'msvc_objs')
if os.path.exists(obj_dir):
    shutil.rmtree(obj_dir)
os.makedirs(obj_dir, exist_ok=True)

def find_first_existing(paths, check_subpath=None):
    for p in paths:
        if os.path.exists(p):
            if check_subpath and not os.path.exists(os.path.join(p, check_subpath)):
                continue
            return p
    return paths[0]

msvc_root = find_first_existing([
    r'D:\msvc\VC\Tools\MSVC\14.44.35207',
    r'D:\msvc\VC\Tools\MSVC\14.51.36231',
    r'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207',
    r'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\14.44.35207'
], check_subpath=r'bin\Hostx64\x64\cl.exe')

cl_bin = shutil.which('cl.exe') or os.path.join(msvc_root, 'bin', 'Hostx64', 'x64', 'cl.exe')
link_bin = shutil.which('link.exe') or os.path.join(msvc_root, 'bin', 'Hostx64', 'x64', 'link.exe')

sdk_root = find_first_existing([
    r'F:\Program Files (x86)\Windows Kits\10',
    r'C:\Program Files (x86)\Windows Kits\10',
    r'D:\Windows Kits\10'
], check_subpath='Include')

sdk_ver = '10.0.26100.0'
inc_ver_dir = os.path.join(sdk_root, 'Include')
if os.path.exists(inc_ver_dir):
    vers = [v for v in os.listdir(inc_ver_dir) if v.startswith('10.')]
    if vers:
        sdk_ver = sorted(vers)[-1]

msvc_inc = [p for p in [
    os.path.join(msvc_root, 'include'),
    os.path.join(sdk_root, 'Include', sdk_ver, 'ucrt'),
    os.path.join(sdk_root, 'Include', sdk_ver, 'um'),
    os.path.join(sdk_root, 'Include', sdk_ver, 'shared'),
] if os.path.exists(p)]

msvc_lib = [p for p in [
    os.path.join(msvc_root, 'lib', 'x64'),
    os.path.join(sdk_root, 'Lib', sdk_ver, 'ucrt', 'x64'),
    os.path.join(sdk_root, 'Lib', sdk_ver, 'um', 'x64'),
] if os.path.exists(p)]

ssl_root = find_first_existing([
    os.environ.get('OPENSSL_ROOT_DIR', ''),
    r'C:\Program Files\OpenSSL',
    r'C:\Program Files\OpenSSL-Win64',
    r'D:\Program Files\OpenSSL-Win64',
    r'F:\Program Files\OpenSSL-Win64'
], check_subpath=r'include\openssl\ssl.h')

oc_amr_inc = os.path.join(root, 'third_party', 'opencore-amr', 'include')

inc_dirs = [
    root,
    pj_dir,
    os.path.join(pj_dir, 'pjlib', 'include'),
    os.path.join(pj_dir, 'pjlib-util', 'include'),
    os.path.join(pj_dir, 'pjnath', 'include'),
    os.path.join(pj_dir, 'pjmedia', 'include'),
    os.path.join(pj_dir, 'pjsip', 'include'),
    os.path.join(pj_dir, 'third_party', 'resample', 'include'),
    os.path.join(pj_dir, 'third_party', 'resample', 'src'),
    oc_amr_inc,
    os.path.join(ssl_root, 'include'),
] + msvc_inc

oc_amr_lib = os.path.join(root, 'third_party', 'opencore-amr', 'lib')

lib_dirs = msvc_lib + [
    os.path.join(ssl_root, 'lib', 'VC', 'x64', 'MD'),
    os.path.join(ssl_root, 'lib'),
    oc_amr_lib,
]

subdirs = [
    ('pjlib', 'src', 'pj'),
    ('pjlib-util', 'src', 'pjlib-util'),
    ('pjnath', 'src', 'pjnath'),
    ('pjmedia', 'src', 'pjmedia'),
    ('pjmedia', 'src', 'pjmedia-audiodev'),
    ('pjmedia', 'src', 'pjmedia-codec'),
    ('third_party', 'resample', 'src'),
    ('pjsip', 'src', 'pjsip'),
    ('pjsip', 'src', 'pjsip-ua'),
    ('pjsip', 'src', 'pjsip-simple'),
    ('pjsip', 'src', 'pjsua-lib'),
]

# Files to EXCLUDE from compilation
exact_excludes = [
    'main.c', 'milenage.c', 'speex_codec.c', 'echo_speex.c',
    'g722.c', 'g7221.c', 'gsm.c', 'ilbc.c',
    'transport_srtp.c', 'transport_srtp_sdes.c', 'transport_srtp_dtls.c',
    'guid_android.c', 'guid_bsd.c', 'guid_darwin.c', 'guid_uuid.c',
    'ioqueue_common_abs.c', 'ioqueue_dummy.c', 'ioqueue_epoll.c', 'ioqueue_kqueue.c',
    'log_writer_printk.c', 'os_rwmutex.c', 'os_time_unix.c', 'pool_policy_kmalloc.c',
    'scanner_cis_bitwise.c', 'scanner_cis_uint.c',
    'file_access_unistd.c', 'file_io_ansi.c', 'guid_simple.c',
    'ioqueue_select.c', 'os_time_bsd.c', 'os_timestamp_posix.c',
    'os_error_unix.c', 'os_core_unix.c',
    'ip_helper_generic.c', 'ip_helper_winphone8.c',
    # QoS: exclude non-Windows implementations (we use sock_qos_dummy.c via PJ_QOS_IMPLEMENTATION=PJ_QOS_DUMMY)
    'sock_qos_bsd.c', 'sock_qos_darwin.c', 'sock_qos_wm.c',
    # SSL: exclude non-OpenSSL implementations (we use ssl_sock_ossl.c with OpenSSL)
    # ssl_sock_imp_common.c is #included from ssl_sock_ossl.c, not compiled separately
    'ssl_sock_gtls.c', 'ssl_sock_darwin.c', 'ssl_sock_schannel.c', 'ssl_sock_imp_common.c',
    'extra-exports.c'
]

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
                if fname in exact_excludes or any(fname.startswith(k) for k in exclude_prefixes):
                    continue
                c_files.append(os.path.join(dpath, f))

inc_cmd = " ".join([f'/I"{d}"' for d in inc_dirs])
defs = '/DPJ_WIN32=1 /DPJ_M_X86_64=1 /D_CRT_SECURE_NO_WARNINGS /D_WINSOCK_DEPRECATED_NO_WARNINGS /DPJ_QOS_IMPLEMENTATION=PJ_QOS_DUMMY /DPJMEDIA_HAS_SRTP=0 /DPJMEDIA_HAS_SPEEX_CODEC=0 /DPJMEDIA_HAS_SPEEX_AEC=0 /DPJMEDIA_HAS_ILBC_CODEC=0 /DPJMEDIA_HAS_G722_CODEC=0 /DPJMEDIA_HAS_GSM_CODEC=0 /DPJMEDIA_HAS_G711_CODEC=1 /DPJMEDIA_HAS_OPENCORE_AMRNB_CODEC=1 /DPJMEDIA_HAS_OPENCORE_AMRWB_CODEC=0 /DPJMEDIA_AUTO_LINK_OPENCORE_AMR_LIBS=0'

failed_files = []

def compile_file(item):
    i, src = item
    base_name = os.path.basename(src).replace('.cpp', '.obj').replace('.c', '.obj')
    obj_path = os.path.join(obj_dir, f"{i}_{base_name}")
    cpp_flags = "/EHsc /std:c++17" if src.endswith('.cpp') else ""
    cmd = f'"{cl_bin}" /c /O2 /nologo {cpp_flags} {defs} {inc_cmd} "{src}" /Fo"{obj_path}"'
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        if 'b2bua' in src:
            print(f"\n[COMPILE ERROR in {src}]:\n{res.stderr}\n{res.stdout}\n")
        failed_files.append((src, res.stderr[:200]))
        return None
    return obj_path

print(f"Compiling {len(c_files)} files with MSVC cl.exe in parallel...")
with ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(compile_file, enumerate(c_files)))

valid_objs = [os.path.normpath(o) for o in results if o and os.path.exists(o)]
print(f"Successfully compiled {len(valid_objs)} / {len(c_files)} MSVC object files.")
if failed_files:
    print(f"\n{len(failed_files)} files failed to compile:")
    for src, err in failed_files:
        print(f"  FAIL: {os.path.basename(src)}: {err[:100]}")

# Write response file for linker
rsp_path = os.path.join(root, 'msvc_objs.rsp')
with open(rsp_path, 'w') as f:
    for vo in valid_objs:
        f.write(f'"{vo}"\n')

lib_flags = " ".join([f'/LIBPATH:"{d}"' for d in lib_dirs])
sys_libs = 'ws2_32.lib wsock32.lib ole32.lib winmm.lib wininet.lib winhttp.lib iphlpapi.lib bcrypt.lib advapi32.lib user32.lib libssl.lib libcrypto.lib crypt32.lib opencore-amrnb.lib'

link_cmd = f'"{link_bin}" /NOLOGO @msvc_objs.rsp /OUT:b2bua_msvc.exe {lib_flags} {sys_libs}'

print("\nLinking native MSVC executable b2bua_msvc.exe...")
res = subprocess.run(link_cmd, shell=True, capture_output=True, text=True)

if os.path.exists('b2bua_msvc.exe'):
    bin_dir = os.path.join(root, 'bin')
    win_dir = os.path.join(bin_dir, 'windows-x64')
    os.makedirs(bin_dir, exist_ok=True)
    os.makedirs(win_dir, exist_ok=True)

    # Terminate running b2bua_msvc.exe process if locked
    try:
        subprocess.run('taskkill /F /IM b2bua_msvc.exe', shell=True, capture_output=True)
    except Exception:
        pass

    try:
        shutil.copy('b2bua_msvc.exe', os.path.join(bin_dir, 'b2bua_msvc.exe'))
        shutil.copy('b2bua_msvc.exe', os.path.join(win_dir, 'b2bua_msvc.exe'))
    except Exception as e:
        print(f"\nNote: Could not copy executable to bin folder ({e}). The newly built binary is available at b2bua_msvc.exe.")

    if os.path.exists(os.path.join(root, '.env')):
        try:
            shutil.copy(os.path.join(root, '.env'), os.path.join(win_dir, '.env'))
        except Exception:
            pass
    sz = os.path.getsize('b2bua_msvc.exe')
    print(f"\n=== SUCCESS! ===")
    print(f"b2bua_msvc.exe ({sz:,} bytes / {sz/1024:.0f} KB)")
    print(f"100% native MSVC Windows executable - no WSL, no Python, no MinGW needed!")
else:
    print(f"\nMSVC Link error:\n{res.stderr[:2000]}")
    print(f"MSVC Link stdout:\n{res.stdout[:2000]}")
