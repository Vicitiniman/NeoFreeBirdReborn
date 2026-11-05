"""Validate the host's private Likes contract without executing or extracting it."""
from pathlib import Path
import argparse
import json
import plistlib
import re
import struct
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class HostContractError(ValueError):
    pass


def contract():
    text = (ROOT / 'src/Likes/BHTNativeLikesContract.h').read_text(encoding='utf8')
    names = ['kBHTEntryFactoryOffset', 'kBHTEntryFactoryJumpTableOffset',
             'kBHTBookmarksFactoryCaseOffset', 'kBHTBookmarksFactoryJump']
    result = {name: int(re.search(r'\b' + name + r'\s*=\s*(0x[0-9a-fA-F]+)', text)[1], 16)
              for name in names}
    for name in ['kBHTT1TwitterUUID', 'kBHTEntryFactoryPrologue', 'kBHTBookmarksFactoryCase']:
        values = re.search(r'\b' + name + r'\[[^\]]*\]\s*=\s*\{([^}]+)\}', text)[1]
        result[name] = [int(n, 16) for n in re.findall(r'0x[0-9a-fA-F]+', values)]
    support = (ROOT / 'src/Compatibility/BHTHostCompatibility.m').read_text(encoding='utf8')
    for key in ['BHTTargetAppVersion', 'BHTTargetAppBuild']:
        result[key] = re.search(r'\b' + key + r'\s*=\s*@"([^"]+)"', support)[1]
    return result


def arm64_slice(data):
    if data[:4] == b'\xcf\xfa\xed\xfe':
        if struct.unpack_from('<I', data, 4)[0] != 0x100000C:
            raise HostContractError('T1Twitter is not arm64')
        return data
    if data[:4] not in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        raise HostContractError('T1Twitter is not a supported Mach-O image')
    count = struct.unpack_from('>I', data, 4)[0]
    wide = data[:4] == b'\xca\xfe\xba\xbf'
    size = 32 if wide else 20
    if count > 32 or 8 + count * size > len(data):
        raise HostContractError('Invalid universal image header')
    for i in range(count):
        at = 8 + i * size
        cpu = struct.unpack_from('>I', data, at)[0]
        if cpu != 0x100000C:
            continue
        offset, length = struct.unpack_from('>QQ' if wide else '>II', data, at + 8)
        if offset + length > len(data):
            raise HostContractError('Truncated arm64 slice')
        return arm64_slice(data[offset:offset + length])
    raise HostContractError('No arm64 slice in T1Twitter')


def inspect_framework(data, expected=None):
    expected = expected or contract()
    data = arm64_slice(data)
    commands, command_bytes = struct.unpack_from('<II', data, 16)
    if commands > 4096 or 32 + command_bytes > len(data):
        raise HostContractError('Invalid Mach-O commands')
    segments = []
    identity = None
    cursor = 32
    for _ in range(commands):
        cmd, size = struct.unpack_from('<II', data, cursor)
        if size < 8 or cursor + size > 32 + command_bytes:
            raise HostContractError('Truncated Mach-O command')
        if cmd == 0x1B and size >= 24:
            identity = bytes(data[cursor + 8:cursor + 24])
        elif cmd == 0x19 and size >= 72:
            address, virtual_size, offset, length = struct.unpack_from('<QQQQ', data, cursor + 24)
            if offset + length > len(data):
                raise HostContractError('Truncated Mach-O segment')
            segments.append((address, offset, length))
        elif cmd in (0x21, 0x2C) and size >= 20:
            if struct.unpack_from('<I', data, cursor + 16)[0]:
                raise HostContractError('T1Twitter is encrypted')
        cursor += size
    if identity != bytes(expected['kBHTT1TwitterUUID']):
        raise HostContractError('Unverified T1Twitter UUID; private Likes offsets are not valid for this image')
    base = min((a for a, o, length in segments if o == 0 and length), default=0)

    def raw(offset, size):
        address = base + offset
        for start, file_offset, length in segments:
            if start <= address and address + size <= start + length:
                at = file_offset + address - start
                return data[at:at + size]
        raise HostContractError('Private factory contract points outside file-backed segments')

    for offset_key, words_key in [('kBHTEntryFactoryOffset', 'kBHTEntryFactoryPrologue'),
                                   ('kBHTBookmarksFactoryCaseOffset', 'kBHTBookmarksFactoryCase')]:
        words = expected[words_key]
        actual = raw(expected[offset_key], len(words) * 4)
        if actual != struct.pack('<' + 'I' * len(words), *words):
            raise HostContractError(f'Native factory instructions changed: {words_key}')
    jump = struct.unpack('<H', raw(expected['kBHTEntryFactoryJumpTableOffset'] + 6 * 2, 2))[0]
    if jump != expected['kBHTBookmarksFactoryJump']:
        raise HostContractError('Bookmarks is not at the verified 16-bit panel-6 switch target')
    target = expected['kBHTEntryFactoryOffset'] + 64 + jump * 4
    if target != expected['kBHTBookmarksFactoryCaseOffset']:
        raise HostContractError('Jump target does not match the native Bookmarks case')
    return {'frameworkUUID': str(uuid.UUID(bytes=identity)), 'jumpTableBits': 16,
            'bookmarksPanel': 6, 'nativeFactoryContract': 'matched'}


def validate_ipa(path):
    expected = contract()
    with zipfile.ZipFile(path) as archive:
        plists = [n for n in archive.namelist()
                  if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
        if len(plists) != 1:
            raise HostContractError('Expected one main app in the IPA')
        info = plistlib.loads(archive.read(plists[0]))
        if info.get('CFBundleShortVersionString') != expected['BHTTargetAppVersion'] or \
                str(info.get('CFBundleVersion')) != expected['BHTTargetAppBuild']:
            raise HostContractError('This port requires X 12.40.1 build 1')
        if info.get('CFBundleIdentifier') != 'com.atebits.Tweetie2':
            raise HostContractError('Expected the original X bundle before packaging')
        prefix = plists[0].removesuffix('Info.plist')
        result = inspect_framework(archive.read(prefix + 'Frameworks/T1Twitter.framework/T1Twitter'), expected)
        return {'appVersion': info['CFBundleShortVersionString'], 'appBuild': str(info['CFBundleVersion']), **result}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(validate_ipa(args.ipa), indent=2))
    except (HostContractError, KeyError, struct.error, zipfile.BadZipFile) as error:
        parser.exit(1, f'Host compatibility validation failed: {error}\n')
