"""Check the first-frame launch texture without needing an IPA or iOS tools."""

import binascii
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "layout/Library/Application Support/BHT/BHTwitter.bundle"
spec = importlib.util.spec_from_file_location("ipa_branding", ROOT / "branding/ipa_branding.py")
branding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(branding)


def rgba_pixels(path):
    raw = path.read_bytes()
    chunks = {}
    offset = 8
    while offset < len(raw):
        size = struct.unpack_from(">I", raw, offset)[0]
        kind = raw[offset + 4:offset + 8]
        data = raw[offset + 8:offset + 8 + size]
        checksum = struct.unpack_from(">I", raw, offset + 8 + size)[0]
        assert binascii.crc32(kind + data) & 0xffffffff == checksum
        chunks.setdefault(kind, bytearray()).extend(data)
        offset += 12 + size
    width, height, depth, color, *_ = struct.unpack(">IIBBBBB", chunks[b"IHDR"])
    assert depth == 8 and color == 6
    packed = zlib.decompress(chunks[b"IDAT"])
    stride = width * 4
    result = bytearray()
    previous = bytearray(stride)
    for row in range(height):
        offset = row * (stride + 1)
        filter_kind = packed[offset]
        scanline = bytearray(packed[offset + 1:offset + 1 + stride])
        for index in range(stride):
            left = scanline[index - 4] if index >= 4 else 0
            above = previous[index]
            upper_left = previous[index - 4] if index >= 4 else 0
            if filter_kind == 0:
                predictor = 0
            elif filter_kind == 1:
                predictor = left
            elif filter_kind == 2:
                predictor = above
            elif filter_kind == 3:
                predictor = (left + above) // 2
            elif filter_kind == 4:
                estimate = left + above - upper_left
                predictor = min((left, above, upper_left), key=lambda v: abs(estimate - v))
            else:
                raise AssertionError(f"Unexpected PNG filter {filter_kind}")
            scanline[index] = (scanline[index] + predictor) & 255
        result.extend(scanline)
        previous = scanline
    return width, height, result


class LaunchBrandingTests(unittest.TestCase):
    def test_bird_shape_is_consistent_across_display_scales(self):
        shapes = []
        for suffix, size in (("", 256), ("@2x", 512), ("@3x", 768)):
            width, height, pixels = rgba_pixels(BUNDLE / f"twitter_bird_launch{suffix}.png")
            self.assertEqual((width, height), (size, size))
            opaque = [i for i, alpha in enumerate(pixels[3::4]) if alpha >= 128]
            xs = [i % width for i in opaque]
            ys = [i // width for i in opaque]
            shapes.append((
                (max(xs) - min(xs) + 1) / width,
                (max(ys) - min(ys) + 1) / height,
                sum(xs) / len(xs) / width,
                sum(ys) / len(ys) / height,
            ))
        for shape in shapes[1:]:
            for actual, expected in zip(shape, shapes[0]):
                self.assertAlmostEqual(actual, expected, delta=2 / 256)

    def test_system_splash_uses_the_animation_texture_and_preserves_nib_layout(self):
        archive = b"layout-and-constraints\0xLogo\0unchanged-tail"
        with tempfile.TemporaryDirectory(prefix="nfb-launch-") as directory:
            app = Path(directory)
            nib = app / "LaunchScreen.nib"
            nib.write_bytes(archive)
            branding._apply_builtin_launch_bird(app, app)
            self.assertEqual(nib.read_bytes(), archive.replace(b"xLogo", b"tBird"))
            for suffix in ("", "@2x", "@3x"):
                width, height, pixels = rgba_pixels(app / f"tBird{suffix}.png")
                source_w, source_h, source = rgba_pixels(BUNDLE / f"twitter_bird_launch{suffix}.png")
                self.assertEqual((width, height), (source_w, source_h))
                self.assertEqual(pixels[3::4], source[3::4])
                self.assertEqual(set(zip(pixels[0::4], pixels[1::4], pixels[2::4])),
                                 {branding.TWITTER_BLUE})
            # A second pass must not damage the archive or its textures.
            branding._apply_builtin_launch_bird(app, app)
            self.assertEqual(nib.read_bytes(), archive.replace(b"xLogo", b"tBird"))

    def test_unrecognized_launch_nib_is_left_untouched(self):
        with tempfile.TemporaryDirectory(prefix="nfb-launch-") as directory:
            app = Path(directory)
            nib = app / "LaunchScreen.nib"
            nib.write_bytes(b"another-launch-layout")
            branding._apply_builtin_launch_bird(app, app)
            self.assertEqual(nib.read_bytes(), b"another-launch-layout")
            self.assertFalse((app / "tBird.png").exists())


if __name__ == "__main__":
    unittest.main()
