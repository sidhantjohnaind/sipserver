import os
import subprocess

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
cl_bin = r'D:\msvc\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x86\cl.exe'
src_installer = os.path.join(root, 'src', 'installer.cpp')
out_installer = os.path.join(root, 'JioFiber_B2BUA_Setup_x86.exe')

inc_dirs = [
    r'D:\msvc\VC\Tools\MSVC\14.44.35207\include',
    r'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\ucrt',
    r'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\um',
    r'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared',
]

lib_dirs = [
    r'D:\msvc\VC\Tools\MSVC\14.44.35207\lib\x86',
    r'C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\ucrt\x86',
    r'C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x86',
]

inc_cmd = " ".join([f'/I"{d}"' for d in inc_dirs])
lib_flags = " ".join([f'/LIBPATH:"{d}"' for d in lib_dirs])
sys_libs = 'Shell32.lib Advapi32.lib User32.lib Kernel32.lib'

cmd = f'"{cl_bin}" /O2 /EHsc /std:c++17 {inc_cmd} "{src_installer}" /Fe"{out_installer}" /link {lib_flags} {sys_libs}'

print("Building Windows x86 (32-bit) Setup Installer (JioFiber_B2BUA_Setup_x86.exe)...")
res = subprocess.run(cmd, shell=True, capture_output=True, text=True)

if os.path.exists(out_installer):
    sz = os.path.getsize(out_installer)
    print(f"=== SUCCESS! Built {out_installer} ({sz:,} bytes / {sz/1024:.0f} KB) ===")
else:
    print("Compilation Error:\n", res.stderr)
