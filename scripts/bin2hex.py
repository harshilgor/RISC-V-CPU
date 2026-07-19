#!/usr/bin/env python3
"""Convert a flat binary image to word-addressed hex for the SoC ROM loader."""
from __future__ import annotations

import argparse
import struct
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("bin_path", type=Path)
    ap.add_argument("hex_path", type=Path)
    args = ap.parse_args()

    data = args.bin_path.read_bytes()
    # Pad to a multiple of 4 bytes
    if len(data) % 4:
        data += b"\x00" * (4 - len(data) % 4)

    lines = ["@00000000"]
    for i in range(0, len(data), 4):
        word = struct.unpack_from("<I", data, i)[0]
        lines.append(f"{word:08x}")

    args.hex_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {args.hex_path} ({len(data)} bytes, {len(data)//4} words)")


if __name__ == "__main__":
    main()
