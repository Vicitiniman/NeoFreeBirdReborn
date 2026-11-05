import copy
import importlib.util
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('host_contract', ROOT/'tools/validate_host_ipa.py')
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)


class HostContractTests(unittest.TestCase):
    def setUp(self):
        self.contract = copy.deepcopy(host.contract())
        self.contract.update(kBHTEntryFactoryOffset=256,
                             kBHTEntryFactoryJumpTableOffset=448,
                             kBHTBookmarksFactoryCaseOffset=256+64+0x39*4)
        data = bytearray(768)
        struct.pack_into('<8I', data, 0, 0xFEEDFACF, 0x100000C, 0, 6, 3, 120, 0, 0)
        struct.pack_into('<II16sQQQQiiII', data, 32, 0x19, 72, b'__TEXT', 0, 768, 0, 768, 5, 5, 0, 0)
        struct.pack_into('<II', data, 104, 0x1B, 24)
        data[112:128] = bytes(self.contract['kBHTT1TwitterUUID'])
        struct.pack_into('<6I', data, 128, 0x2C, 24, 0, 0, 0, 0)
        for offset_key, words_key in [('kBHTEntryFactoryOffset', 'kBHTEntryFactoryPrologue'),
                                      ('kBHTBookmarksFactoryCaseOffset', 'kBHTBookmarksFactoryCase')]:
            words = self.contract[words_key]
            struct.pack_into('<'+'I'*len(words), data, self.contract[offset_key], *words)
        struct.pack_into('<H', data, 448+6*2, 0x39)
        self.data = data

    def test_matching_arm64_contract(self):
        self.assertEqual(host.inspect_framework(self.data, self.contract)['jumpTableBits'], 16)

    def test_same_version_with_different_image_is_rejected(self):
        self.data[112] ^= 1
        with self.assertRaisesRegex(host.HostContractError, 'UUID'):
            host.inspect_framework(self.data, self.contract)

    def test_changed_native_instructions_are_rejected(self):
        self.data[256+13*4] ^= 1
        with self.assertRaisesRegex(host.HostContractError, 'instructions'):
            host.inspect_framework(self.data, self.contract)

    def test_old_byte_jump_table_cannot_pass_halfword_check(self):
        self.data[448:500] = bytes(52)
        self.data[448+6] = 0x39
        with self.assertRaisesRegex(host.HostContractError, '16-bit'):
            host.inspect_framework(self.data, self.contract)

    def test_encrypted_image_is_rejected(self):
        struct.pack_into('<I', self.data, 144, 1)
        with self.assertRaisesRegex(host.HostContractError, 'encrypted'):
            host.inspect_framework(self.data, self.contract)

    def test_out_of_segment_address_is_rejected(self):
        self.contract['kBHTEntryFactoryJumpTableOffset'] = 800
        with self.assertRaisesRegex(host.HostContractError, 'outside'):
            host.inspect_framework(self.data, self.contract)

    def test_fat_image_selects_the_arm64_slice(self):
        fat = struct.pack('>II5I', 0xCAFEBABE, 1, 0x100000C, 0, 32, len(self.data), 2)
        fat += bytes(32-len(fat)) + self.data
        self.assertEqual(host.inspect_framework(fat, self.contract)['bookmarksPanel'], 6)


if __name__ == '__main__':
    unittest.main()
