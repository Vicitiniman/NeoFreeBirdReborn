#!/usr/bin/env python3
"""Read Objective-C class/method metadata from a local arm64 Mach-O.

This intentionally avoids ktool's full-framework reconstruction, which is slow
for TwitterSPMMigration. It is a read-only helper for targeted ABI comparison.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path


import lief  # type: ignore  # noqa: E402


def parse_binary(path: Path):
    parsed = lief.MachO.parse(str(path))
    if parsed is None or len(parsed) == 0:
        raise RuntimeError(f"Unable to parse Mach-O file: {path}")
    return parsed.at(0)


def mapped(binary, address: int, size: int = 1) -> bool:
    return any(
        int(segment.virtual_address) <= address
        and address + size
        <= int(segment.virtual_address) + int(segment.virtual_size)
        for segment in binary.segments
    )


def raw(binary, address: int, size: int) -> bytes:
    if not mapped(binary, address, size):
        raise ValueError(f"unmapped 0x{address:x}+0x{size:x}")
    return bytes(binary.get_content_from_virtual_address(address, size))


def u32(binary, address: int) -> int:
    return struct.unpack("<I", raw(binary, address, 4))[0]


def s32(binary, address: int) -> int:
    return struct.unpack("<i", raw(binary, address, 4))[0]


def u64(binary, address: int) -> int:
    return struct.unpack("<Q", raw(binary, address, 8))[0]


def resolve_pointer(binary, value: int) -> int:
    if not value:
        return 0
    if mapped(binary, value):
        return value

    # DYLD_CHAINED_PTR_64_OFFSET.
    if (value >> 63) == 0:
        target = (value & ((1 << 36) - 1)) | (((value >> 36) & 0xFF) << 56)
        if mapped(binary, target):
            return target

    # DYLD_CHAINED_PTR_ARM64E rebase (unauthenticated and authenticated forms).
    bind = (value >> 62) & 1
    auth = (value >> 63) & 1
    if not bind:
        if auth:
            target = value & 0xFFFFFFFF
        else:
            target = (value & ((1 << 43) - 1)) | (((value >> 43) & 0xFF) << 56)
        if mapped(binary, target):
            return target

    return value


def pointer(binary, address: int) -> int:
    return resolve_pointer(binary, u64(binary, address))


def cstring(binary, address: int, maximum: int = 4096) -> str | None:
    if not mapped(binary, address):
        return None
    data = bytes(binary.get_content_from_virtual_address(address, maximum))
    value = data.split(b"\0", 1)[0]
    try:
        return value.decode("utf-8")
    except UnicodeDecodeError:
        return None


def objc_section(binary, name: str):
    for section in binary.sections:
        if section.name == name:
            return section
    return None


def class_ro(binary, class_address: int) -> int:
    # class_t.data is the fifth pointer. Its low flag bits are not an address.
    data = pointer(binary, class_address + 32)
    return data & ~0x7


def class_name(binary, class_address: int) -> str | None:
    ro = class_ro(binary, class_address)
    if not mapped(binary, ro, 72):
        return None
    return cstring(binary, pointer(binary, ro + 24))


def method_list(binary, list_address: int):
    if not mapped(binary, list_address, 8):
        return
    entsize_flags = u32(binary, list_address)
    count = u32(binary, list_address + 4)
    relative = bool(entsize_flags & 0x80000000)
    direct_selectors = bool(entsize_flags & 0x40000000)
    entry_size = entsize_flags & 0xFFFF
    if entry_size == 0:
        entry_size = 12 if relative else 24
    if count > 100000:
        return

    for index in range(count):
        entry = list_address + 8 + index * entry_size
        if not mapped(binary, entry, entry_size):
            break
        if relative:
            name_field = entry
            name_target = name_field + s32(binary, name_field)
            if not direct_selectors:
                name_target = pointer(binary, name_target)
            types_field = entry + 4
            imp_field = entry + 8
            types_target = types_field + s32(binary, types_field)
            imp_target = imp_field + s32(binary, imp_field)
        else:
            name_target = pointer(binary, entry)
            types_target = pointer(binary, entry + 8)
            imp_target = pointer(binary, entry + 16)
        yield (
            cstring(binary, name_target),
            cstring(binary, types_target),
            imp_target,
        )


def methods_for_class(binary, class_address: int):
    ro = class_ro(binary, class_address)
    if not mapped(binary, ro, 72):
        return []
    methods = pointer(binary, ro + 32)
    return list(method_list(binary, methods) or [])


def classes(binary):
    section = objc_section(binary, "__objc_classlist")
    if section is None:
        return
    start = int(section.virtual_address)
    size = int(section.size)
    for offset in range(0, size, 8):
        address = pointer(binary, start + offset)
        if mapped(binary, address, 40):
            yield address

