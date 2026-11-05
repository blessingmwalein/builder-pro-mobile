"""Checks a release bundle before it is uploaded to Google Play.

Run from the builder-pro-mobile folder:
  python tool/check_bundle.py [path\\to\\app-release.aab]

Google Play requires the native libraries (.so) of 64-bit apps to be aligned for 16 KB
memory pages. This reads every .so in the bundle and checks that each LOAD segment is
aligned to at least 16384 bytes. It also lists the size of each ABI's libraries.
Exit status is 1 when a 64-bit library is not aligned.
"""

import os
import struct
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT = os.path.join(ROOT, "build", "app", "outputs", "bundle", "release", "app-release.aab")

PT_LOAD = 1
NEEDED = 16384
ABIS_64 = ("arm64-v8a", "x86_64")


def min_load_align(data):
    """Smallest p_align over the LOAD segments of a 64-bit little-endian ELF, else None."""
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        return None
    (phoff,) = struct.unpack_from("<Q", data, 0x20)
    phentsize, phnum = struct.unpack_from("<HH", data, 0x36)
    aligns = []
    for i in range(phnum):
        base = phoff + i * phentsize
        (p_type,) = struct.unpack_from("<I", data, base)
        if p_type == PT_LOAD:
            (p_align,) = struct.unpack_from("<Q", data, base + 0x30)
            aligns.append(p_align)
    return min(aligns) if aligns else None


def main(path):
    if not os.path.exists(path):
        print("not found:", path)
        return 2
    bad = []
    sizes = {}
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            parts = info.filename.split("/")
            if len(parts) < 4 or parts[-3] != "lib" or not parts[-1].endswith(".so"):
                continue
            abi = parts[-2]
            sizes[abi] = sizes.get(abi, 0) + info.file_size
            if abi not in ABIS_64:
                continue
            align = min_load_align(z.read(info))
            if align is None or align < NEEDED:
                bad.append((info.filename, align))
    print(f"{os.path.relpath(path, ROOT)}: {os.path.getsize(path) / 1e6:.1f} MB")
    for abi, total in sorted(sizes.items()):
        print(f"  {abi}: native libraries {total / 1e6:.1f} MB")
    if bad:
        print("NOT 16 KB aligned:")
        for name, align in bad:
            print(f"  {name} (alignment {align})")
        return 1
    print("every 64-bit native library is aligned for 16 KB pages")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else DEFAULT))
