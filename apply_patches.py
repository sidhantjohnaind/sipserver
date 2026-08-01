#!/usr/bin/env python3
"""
Apply JioFiber B2BUA patches to stock PJSIP 2.15.1 source.

Usage:
    python apply_patches.py

Run this ONCE after downloading PJSIP 2.15.1 into third_party/pjproject-2.15.1/
"""
import os, subprocess, sys

root = os.path.dirname(os.path.abspath(__file__))
pjsip_dir = os.path.join(root, "third_party", "pjproject-2.15.1")
patches_dir = os.path.join(root, "patches")

if not os.path.isdir(pjsip_dir):
    print(f"ERROR: PJSIP not found at {pjsip_dir}")
    print("Download PJSIP 2.15.1 from https://github.com/pjsip/pjproject/releases/tag/2.15.1")
    print("and extract it to third_party/pjproject-2.15.1/")
    sys.exit(1)

patches = [
    # (patch file, description)
    ("pjmedia_src_pjmedia-codec_opencore_amr_c.patch",
     "opencore_amr.c: octet-align=1, bitrate=12200 (Jio VoLTE Mode 7), mode-set fmtp, VAD off"),
    ("pjmedia_src_pjmedia_stream_c.patch",
     "stream.c: JB frame-type logging for debugging"),
]

ok = 0
for patch_file, desc in patches:
    patch_path = os.path.join(patches_dir, patch_file)
    if not os.path.exists(patch_path):
        print(f"SKIP (not found): {patch_file}")
        continue
    print(f"Applying: {patch_file}")
    print(f"  {desc}")
    result = subprocess.run(
        ["patch", "-p1", "--forward", "-i", patch_path],
        cwd=pjsip_dir,
        capture_output=True, text=True
    )
    if result.returncode == 0 or "already applied" in result.stdout:
        print(f"  OK\n")
        ok += 1
    else:
        print(f"  FAILED:\n{result.stdout}\n{result.stderr}\n")

print(f"Applied {ok}/{len(patches)} patches.")
if ok == len(patches):
    print("All patches applied. You can now build with src/build_*.py")
