"""
Surgical 2-point patch for nvlddmkm.sys, driver 582.99.

Gate 1: forces a display-init function's return value from an internal error
         code (0x56) to success (0x00).
Gate 2: flips a conditional jump (JNZ -> JZ) that gates WDDM mode on Tesla
         cards behind the AllowWddmOnTesla license check. A condition flip is
         used instead of an unconditional JMP because this instruction sits
         inside a loop; overwriting it with JMP would also break the loop's
         normal iteration logic, not just the one check.

Both offsets are read-verified against the exact original bytes before
anything is written. If either doesn't match, nothing is written at all.

Usage:
    python patch_p40_wddm.py <source .sys> <destination .sys>

Source and destination may be the same path.
"""

import os
import sys

# Gate 1: MOV EAX, 0x56  ->  MOV EAX, 0x00
GATE1_OFFSET   = 0x7D184
GATE1_ORIGINAL = bytes.fromhex("B8 56 00 00 00".replace(" ", ""))
GATE1_PATCHED  = bytes.fromhex("B8 00 00 00 00".replace(" ", ""))

# Gate 2: JNZ -> JZ (opcode 0F 85 -> 0F 84), verified together with 10 bytes
# of surrounding context to make sure we're patching the right instruction.
GATE2_OFFSET   = 0x1815EA9
GATE2_ORIGINAL = bytes.fromhex(
    "44 38 35 F0 BA 92 FF 41 8B CF 0F 85 5C 01 00 00".replace(" ", ""))
GATE2_PATCHED = bytes.fromhex(
    "44 38 35 F0 BA 92 FF 41 8B CF 0F 84 5C 01 00 00".replace(" ", ""))

PATCHES = [
    {"name": "Gate 1 (display init return value)",
     "offset": GATE1_OFFSET, "original": GATE1_ORIGINAL, "patched": GATE1_PATCHED},
    {"name": "Gate 2 (AllowWddmOnTesla branch, JNZ->JZ)",
     "offset": GATE2_OFFSET, "original": GATE2_ORIGINAL, "patched": GATE2_PATCHED},
]


def patch_driver(src_path: str, dst_path: str) -> bool:
    if not os.path.exists(src_path):
        print(f"[-] Source file not found: {src_path}")
        return False

    with open(src_path, "rb") as f:
        data = bytearray(f.read())

    orig_size = len(data)
    expected_diffs = set()

    for p in PATCHES:
        off, orig, new = p["offset"], p["original"], p["patched"]
        actual = bytes(data[off:off + len(orig)])

        if actual == new:
            print(f"[!] {p['name']}: already patched, skipping.")
            continue
        if actual != orig:
            print(f"[-] ABORT at {p['name']}: bytes at offset 0x{off:X} don't "
                  f"match the expected original.")
            print(f"    Expected: {orig.hex(' ')}")
            print(f"    Found:    {actual.hex(' ')}")
            print("    -> Likely a different driver version. Nothing written.")
            return False

        data[off:off + len(new)] = new
        for i in range(len(orig)):
            if orig[i] != new[i]:
                expected_diffs.add(off + i)
        print(f"[+] {p['name']}: patch staged (offset 0x{off:X}).")

    same_file = os.path.abspath(src_path) == os.path.abspath(dst_path)
    if not same_file and os.path.exists(dst_path):
        print(f"[-] ABORT: destination already exists and differs from source, "
              f"won't overwrite: {dst_path}")
        return False

    with open(dst_path, "wb") as f_new:
        f_new.write(bytes(data))

    # --- verification ---
    ok = True
    new_size = os.path.getsize(dst_path)
    if new_size != orig_size:
        print(f"[-] VERIFICATION FAILED: file size changed "
              f"({orig_size} -> {new_size}).")
        ok = False
    else:
        print(f"[+] Verified: file size unchanged ({orig_size} bytes).")

    with open(dst_path, "rb") as f:
        dst_full = f.read()
    with open(src_path, "rb") as f:
        src_full = f.read() if not same_file else bytes(data)
    # if same_file, src_full was already overwritten on disk, so compare
    # dst_full against the in-memory pre-patch state isn't meaningful here;
    # instead just verify each patched region directly.

    for p in PATCHES:
        off, new = p["offset"], p["patched"]
        region = dst_full[off:off + len(new)]
        if region == new:
            print(f"[+] Verified {p['name']}: offset 0x{off:X} now contains "
                  f"{new.hex(' ')}.")
        else:
            print(f"[-] VERIFICATION FAILED for {p['name']}: found "
                  f"{region.hex(' ')}, expected {new.hex(' ')}.")
            ok = False

    if ok:
        print(f"\n[+] All checks passed. Patched driver written to: {dst_path}")
    else:
        print(f"\n[-] Verification failed. Do not use: {dst_path}")
    return ok


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python patch_p40_wddm.py <source nvlddmkm.sys> "
              "<destination nvlddmkm.sys>")
        sys.exit(1)
    src, dst = sys.argv[1], sys.argv[2]
    success = patch_driver(src, dst)
    sys.exit(0 if success else 1)
