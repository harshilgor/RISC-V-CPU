#!/usr/bin/env python3
"""Build a ROM hex image from an ELF (PT_LOAD by physical/LMA address).

Only addresses in [0, rom_size) are emitted — suitable for the teaching SoC
ROM loader. .data that is linked VMA=RAM / LMA=ROM is placed at its LMA so
crt0 can copy it into RAM at runtime.
"""
from __future__ import annotations

import argparse
import struct
from pathlib import Path


def read_elf_rom(path: Path, rom_size: int) -> bytearray:
    data = path.read_bytes()
    if data[:4] != b"\x7fELF":
        raise SystemExit(f"Not an ELF file: {path}")

    (
        _e_ident,
        e_type,
        e_machine,
        e_version,
        e_entry,
        e_phoff,
        e_shoff,
        e_flags,
        e_ehsize,
        e_phentsize,
        e_phnum,
        e_shentsize,
        e_shnum,
        e_shstrndx,
    ) = struct.unpack_from("<16sHHIIIIIHHHHHH", data, 0)

    if e_ident_class(data) != 1:
        raise SystemExit("Only ELF32 is supported")

    rom = bytearray(rom_size)
    used = 0

    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = (
            struct.unpack_from("<IIIIIIII", data, off)
        )
        if p_type != 1:  # PT_LOAD
            continue
        if p_filesz == 0:
            continue
        # Physical address = LMA (where the bytes live in the ROM image)
        if p_paddr >= rom_size:
            continue
        end = min(p_paddr + p_filesz, rom_size)
        chunk = data[p_offset : p_offset + (end - p_paddr)]
        rom[p_paddr:end] = chunk
        used = max(used, end)

    if used == 0:
        raise SystemExit("No PT_LOAD segments landed in ROM")

    # Trim trailing zeros but keep word alignment
    while used > 0 and rom[used - 1] == 0:
        used -= 1
    if used % 4:
        used += 4 - (used % 4)
    return rom[:used]


def e_ident_class(data: bytes) -> int:
    return data[4]


def write_hex(rom: bytes, out: Path) -> None:
    lines = ["@00000000"]
    for i in range(0, len(rom), 4):
        word = struct.unpack_from("<I", rom, i)[0]
        lines.append(f"{word:08x}")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out} ({len(rom)} bytes, {len(rom)//4} words)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("elf_path", type=Path)
    ap.add_argument("hex_path", type=Path)
    ap.add_argument("--rom-size", type=lambda s: int(s, 0), default=0x10000)
    args = ap.parse_args()

    rom = read_elf_rom(args.elf_path, args.rom_size)
    write_hex(rom, args.hex_path)


if __name__ == "__main__":
    main()
