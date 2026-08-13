import os
import tarfile
import stat

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
appimage_path = os.path.join(root, 'JioFiber_B2BUA-x86_64.AppImage')
linux_bin = os.path.join(root, 'bin', 'linux-amd64', 'b2bua')

if not os.path.exists(linux_bin):
    linux_bin = os.path.join(root, 'b2bua')

if not os.path.exists(linux_bin):
    print("Error: linux-amd64 b2bua binary not found!")
    exit(1)

with open(linux_bin, 'rb') as f:
    bin_data = f.read()

# Self-extracting AppImage Shell Header
runtime_header = b"""#!/bin/sh
# JioFiber SIP B2BUA Linux AppImage Launcher
set -e

TMP_DIR="$(mktemp -d -t jio_b2bua_appimage_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

SKIP=$(awk '/^__PAYLOAD_BEGINS_BELOW__/ {print NR + 1; exit 0;}' "$0")
tail -n +$SKIP "$0" | tar -xz -C "$TMP_DIR"

chmod +x "$TMP_DIR/usr/bin/b2bua"
exec "$TMP_DIR/usr/bin/b2bua" "$@"
exit 0
__PAYLOAD_BEGINS_BELOW__
"""

tar_path = os.path.join(root, 'payload.tar.gz')
with tarfile.open(tar_path, 'w:gz') as tar:
    # Add usr/bin/b2bua
    tarinfo = tarfile.TarInfo(name='usr/bin/b2bua')
    tarinfo.size = len(bin_data)
    tarinfo.mode = 0o755
    tar.addfile(tarinfo, fileobj=open(linux_bin, 'rb'))
    
    # Add AppRun
    apprun_code = b"#!/bin/sh\nexec $(dirname $0)/usr/bin/b2bua \"$@\"\n"
    apprun_info = tarfile.TarInfo(name='AppRun')
    apprun_info.size = len(apprun_code)
    apprun_info.mode = 0o755
    import io
    tar.addfile(apprun_info, fileobj=io.BytesIO(apprun_code))

with open(tar_path, 'rb') as f:
    payload_data = f.read()

with open(appimage_path, 'wb') as f:
    f.write(runtime_header)
    f.write(payload_data)

os.remove(tar_path)
os.chmod(appimage_path, os.stat(appimage_path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

sz = os.path.getsize(appimage_path)
print(f"Successfully built standalone Linux AppImage: {appimage_path} ({sz:,} bytes / {sz/1024:.0f} KB)")
