#!/usr/bin/env python3
"""
patch_p40_wddm.py - Surgical 2-Point Patcher for NVIDIA Tesla P40 WDDM Reactivation
Target Driver: nvlddmkm.sys (v551.86 x64)

Changes:
  1. Gate 1 (Display Driver Subsystem Entry Gate):
     Offset 0x27473F: B8 56 00 00 00 -> B8 00 00 00 00  (MOV EAX, 0x0)
  2. Gate 2 (AllowWddmOnTesla WDDM Gate in FUN_1414375a0):
     Offset 0x1328EFC: 0F 85 54 01 00 00 -> E9 55 01 00 00 90 (JMP 0x141438656; NOP)

Total bytes modified: Exactly 6 bytes across the entire ~60 MB binary.
"""

import sys
import os

PATCHES = [
    {
        "name": "Gate 1 (Display Driver Subsystem Gate)",
        "offset": 0x27473F,
        "orig": bytes.fromhex("B8 56 00 00 00"),
        "patch": bytes.fromhex("B8 00 00 00 00")
    },
    {
        "name": "Gate 2 (AllowWddmOnTesla Gate in FUN_1414375a0)",
        "offset": 0x1328EFC,
        "orig": bytes.fromhex("0F 85 54 01 00 00"),
        "patch": bytes.fromhex("E9 55 01 00 00 90")
    }
]

def patch_file(src_path: str, dst_path: str) -> bool:
    if not os.path.isfile(src_path):
        print(f"[-] Error: Source file not found: {src_path}")
        return False

    with open(src_path, "rb") as f:
        data = bytearray(f.read())

    orig_len = len(data)
    print(f"[*] Reading: {src_path} ({orig_len:,} bytes)")

    for p in PATCHES:
        name = p["name"]
        off = p["offset"]
        orig = p["orig"]
        patch = p["patch"]

        current = bytes(data[off:off + len(orig)])
        if current == patch:
            print(f"[!] {name} at 0x{off:06X} is ALREADY patched.")
        elif current == orig:
            data[off:off + len(patch)] = patch
            print(f"[+] {name} at 0x{off:06X} patched successfully.")
        else:
            print(f"[-] ERROR: Unexpected bytes at offset 0x{off:06X} for {name}!")
            print(f"    Expected: {orig.hex(' ')}")
            print(f"    Found:    {current.hex(' ')}")
            print("    Aborting. Make sure this is driver version 551.86.")
            return False

    out_dir = os.path.dirname(dst_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(dst_path, "wb") as f_out:
        f_out.write(data)

    print(f"\n[+] Success! Patched driver written to: {dst_path}")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python patch_p40_wddm.py <input_nvlddmkm.sys> <output_nvlddmkm.sys>")
        sys.exit(1)

    src = sys.argv[1]
    dst = sys.argv[2]
    ok = patch_file(src, dst)
    sys.exit(0 if ok else 1)
