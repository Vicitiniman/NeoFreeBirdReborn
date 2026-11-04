#!/usr/bin/env python3
"""IPA branding modifications applied to a freshly built .ipa/.tipa.

This is a standalone port of the former ipa-branding.sh. rebrand.sh invokes it
as a subprocess on an already built IPA/TIPA:

    RESOURCE_PACK=... TWITTER_BRANDING=1 TWITTER_APP_ICON=... \
        python3 ipa_branding.py <ipa_path>

It unpacks the IPA once, applies every enabled step — the theme pack in
RESOURCE_PACK, the loose alternate icon in TWITTER_APP_ICON and, when
TWITTER_BRANDING=1, the "Twitter" display name plus blue pre-injection launch
bird — then repackages once. When no branding is enabled it exits 0 without
touching the IPA. A non-zero exit means a requested step failed; rebrand.sh
treats that as fatal.

The sibling helpers (car_extract.m, the .py steps) live alongside this file in
branding/, so they are resolved relative to this file rather than the caller.
"""

import os
import plistlib
import re
import binascii
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

BRANDING_DIR = Path(__file__).resolve().parent

def err(message):
    print(f"Error: {message}", file=sys.stderr)


class BrandingError(Exception):
    """Raised for a failed branding step; maps to a fatal non-zero exit."""


def _have(cmd):
    return shutil.which(cmd) is not None


def _run(args, **kwargs):
    """Run a command, returning True on success (exit 0)."""
    return subprocess.run(args, **kwargs).returncode == 0


def _find(root, predicate):
    """True if any file under root satisfies predicate(Path)."""
    root = Path(root)
    if not root.exists():
        return False
    for path in root.rglob("*"):
        if path.is_file() and predicate(path):
            return True
    return False


def _is_apple_double(path):
    return path.name.startswith("._")


# --- display name and built-in alternate icon -------------------------------

def _write_binary_plist(path, data):
    with open(path, "wb") as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)


def _set_localized_display_name(path):
    """Update a localized InfoPlist.strings without assuming its encoding."""
    try:
        with open(path, "rb") as f:
            data = plistlib.load(f)
        if isinstance(data, dict):
            data["CFBundleDisplayName"] = "Twitter"
            _write_binary_plist(path, data)
            return
    except (OSError, plistlib.InvalidFileException):
        pass

    raw = path.read_bytes()
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        candidates = (("utf-16", "utf-16"),)
    elif raw.startswith(b"\xef\xbb\xbf"):
        candidates = (("utf-8-sig", "utf-8-sig"),)
    else:
        candidates = (("utf-8", "utf-8"),)
    for read_encoding, write_encoding in candidates:
        try:
            text = raw.decode(read_encoding)
        except UnicodeDecodeError:
            continue

        replacement = '"CFBundleDisplayName" = "Twitter";'
        pattern = re.compile(
            r'(?m)^\s*"?CFBundleDisplayName"?\s*=\s*"(?:[^"\\]|\\.)*"\s*;'
        )
        if pattern.search(text):
            text = pattern.sub(replacement, text)
        else:
            text = text.rstrip() + "\n" + replacement + "\n"
        path.write_text(text, encoding=write_encoding)
        return

    raise BrandingError(f"Branding: could not update localized name in {path}")

def _set_display_name_in_app(appdir):
    """Force the on-device app name back to "Twitter"."""
    plist = appdir / "Info.plist"
    if not plist.is_file():
        raise BrandingError("Branding: could not locate app Info.plist")

    with open(plist, "rb") as f:
        data = plistlib.load(f)
    data["CFBundleDisplayName"] = "Twitter"
    _write_binary_plist(plist, data)

    # A localized InfoPlist.strings overrides Info.plist on SpringBoard. Update
    # every shipped localization so the home-screen label cannot fall back to X.
    for localized in appdir.glob("*.lproj/InfoPlist.strings"):
        _set_localized_display_name(localized)


def _resize_icon(source, size, destination):
    """Resize a square icon with a tool available on macOS or common dev hosts."""
    sips = shutil.which("sips")
    if sips and _run(
        [sips, "-z", str(size), str(size), str(source), "--out", str(destination)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ):
        return

    magick = shutil.which("magick")
    if magick and _run(
        [magick, str(source), "-resize", f"{size}x{size}!", str(destination)]
    ):
        return

    convert = shutil.which("convert")
    if convert and _run(
        [convert, str(source), "-resize", f"{size}x{size}!", str(destination)]
    ):
        return

    raise BrandingError(
        "Branding: 'sips' (macOS) or ImageMagick is required to add the Twitter icon"
    )


def _install_alternate_icon_in_app(appdir, icon_path):
    """Add the supplied bird art as a normal loose alternate app icon.

    Loose icon files deliberately avoid rebuilding Assets.car. That preserves
    all stock alternate icons and is supported by UIApplication's public
    setAlternateIconName API.
    """
    icon_path = Path(icon_path).resolve()
    if not icon_path.is_file():
        raise BrandingError(f"Branding: Twitter app icon not found: {icon_path}")

    plist = appdir / "Info.plist"
    if not plist.is_file():
        raise BrandingError("Branding: could not locate app Info.plist")

    # Generate every scale needed by iPhone and iPad. App icons cannot be loaded
    # from the tweak bundle: SpringBoard expects these files beside Info.plist.
    renditions = {
        "BHTTwitterAppIcon20x20": {1: 20, 2: 40, 3: 60},
        "BHTTwitterAppIcon29x29": {1: 29, 2: 58, 3: 87},
        "BHTTwitterAppIcon40x40": {1: 40, 2: 80, 3: 120},
        "BHTTwitterAppIcon60x60": {2: 120, 3: 180},
        "BHTTwitterAppIcon76x76": {1: 76, 2: 152},
        "BHTTwitterAppIcon83_5x83_5": {2: 167},
    }
    for base, scales in renditions.items():
        for scale, pixels in scales.items():
            suffix = "" if scale == 1 else f"@{scale}x"
            _resize_icon(icon_path, pixels, appdir / f"{base}{suffix}.png")

    with open(plist, "rb") as f:
        info = plistlib.load(f)

    def add_alternate(plist_key, files):
        icons = info.get(plist_key)
        if not isinstance(icons, dict):
            icons = {}
        alternates = icons.get("CFBundleAlternateIcons")
        if not isinstance(alternates, dict):
            alternates = {}
        # Omit CFBundleIconName: that key is for an Assets.car app-icon set.
        # CFBundleIconFiles is the correct declaration for these loose PNGs.
        alternates["BHTTwitterBird"] = {
            "CFBundleIconFiles": files,
            "UIPrerenderedIcon": False,
        }
        icons["CFBundleAlternateIcons"] = alternates
        info[plist_key] = icons

    add_alternate(
        "CFBundleIcons",
        [
            "BHTTwitterAppIcon20x20",
            "BHTTwitterAppIcon29x29",
            "BHTTwitterAppIcon40x40",
            "BHTTwitterAppIcon60x60",
        ],
    )
    add_alternate(
        "CFBundleIcons~ipad",
        [
            "BHTTwitterAppIcon20x20",
            "BHTTwitterAppIcon29x29",
            "BHTTwitterAppIcon40x40",
            "BHTTwitterAppIcon76x76",
            "BHTTwitterAppIcon83_5x83_5",
        ],
    )
    _write_binary_plist(plist, info)


# --- resource pack ----------------------------------------------------------

def _apply_resource_pack_to_app(appdir, workdir, zip_path):
    """Overlay replacement images/glyphs from a zip onto the app.

    The pack is a .zip with two optional subfolders plus optional root files:
      icons/  loose images merged into the app's Assets.car (see
              build_merged_car.py). A flat zip (images at the root, no icons/
              folder) is still treated as icons.
      svgs/   vector glyphs copied over matching TwitterAppearance files (see
              override_appearance_svgs.py).
      <root>  non-image files at the zip root (e.g. LaunchScreen.nib) overwrite
              the same-named file in the app root.
    """
    zip_path = Path(zip_path)
    if not zip_path.is_file():
        raise BrandingError(f"Branding: image pack not found: {zip_path}")
    if not _have("unzip"):
        raise BrandingError("Branding: 'unzip' is required for --resource-pack")

    zip_path = zip_path.resolve()
    plist = appdir / "Info.plist"
    car = appdir / "Assets.car"

    pack = workdir / "pack"
    if not _run(["unzip", "-q", "-o", str(zip_path), "-d", str(pack)]):
        raise BrandingError(f"Branding: failed to unpack image pack {zip_path}")

    icons_dir = pack / "icons"
    if not icons_dir.is_dir():
        icons_dir = pack  # back-compat: flat zip
    svgs_dir = pack / "svgs"

    have_icons = _find(
        icons_dir,
        lambda p: p.suffix.lower() in (".png", ".jpg", ".jpeg") and not _is_apple_double(p),
    )
    have_svgs = svgs_dir.is_dir() and _find(
        svgs_dir, lambda p: p.suffix.lower() == ".svg" and not _is_apple_double(p)
    )
    # Non-image files at the pack root overwrite the same-named file in the app
    # root. (Root images belong to the flat-zip icons back-compat path.)
    root_files = [
        p for p in pack.iterdir()
        if p.is_file()
        and p.suffix.lower() not in (".png", ".jpg", ".jpeg", ".svg")
        and not _is_apple_double(p)
    ]
    have_root = bool(root_files)

    if not (have_icons or have_svgs or have_root):
        raise BrandingError(
            "Branding: image pack has no icons/ images, svgs/ glyphs, or root files"
        )

    # --- icons/: merge into Assets.car ---
    if have_icons:
        if not _have("assetutil"):
            raise BrandingError("Branding: 'assetutil' is required for icons/")
        clang_bin = shutil.which("clang") or _xcrun_find("clang")
        actool_bin = shutil.which("actool") or _xcrun_find("actool")
        if not clang_bin:
            raise BrandingError("Branding: 'clang' (Xcode) is required for icons/")
        if not actool_bin:
            raise BrandingError("Branding: 'actool' (Xcode) is required for icons/")
        if not car.is_file():
            raise BrandingError("Branding: app has no Assets.car to merge into")

        clang_log = workdir / "clang.log"
        car_extract = workdir / "car_extract"
        with open(clang_log, "w") as log:
            built = _run(
                [
                    clang_bin, "-fobjc-arc", "-O2",
                    "-framework", "Foundation",
                    "-framework", "CoreGraphics",
                    "-framework", "ImageIO",
                    "-F", "/System/Library/PrivateFrameworks", "-framework", "CoreUI",
                    str(BRANDING_DIR / "car_extract.m"), "-o", str(car_extract),
                ],
                stderr=log,
            )
        if not built:
            err("Branding: failed to build car_extract:")
            sys.stderr.write(clang_log.read_text())
            raise BrandingError("Branding: failed to build car_extract")

        # Aspect-preserving pad helper for master resizes (build_merged_car reads
        # it via NFB_PAD_TOOL); non-fatal if it fails to build (falls back to sips).
        pad_image = workdir / "pad_image"
        with open(clang_log, "a") as log:
            padded = _run(
                [
                    clang_bin, "-fobjc-arc", "-O2",
                    "-framework", "Foundation",
                    "-framework", "CoreGraphics",
                    "-framework", "ImageIO",
                    str(BRANDING_DIR / "pad_image.m"), "-o", str(pad_image),
                ],
                stderr=log,
            )
        if padded:
            os.environ["NFB_PAD_TOOL"] = str(pad_image)

        extract = workdir / "extract"
        if not _run([str(car_extract), str(car), str(extract)]):
            raise BrandingError(f"Branding: failed to extract {car}")

        new_car = workdir / "new.car"
        if not _run([
            sys.executable, str(BRANDING_DIR / "build_merged_car.py"),
            str(car), str(extract), str(icons_dir), str(new_car),
        ]):
            raise BrandingError("Branding: failed to rebuild Assets.car")
        shutil.copyfile(new_car, car)

        if plist.is_file():
            if not _run([
                sys.executable, str(BRANDING_DIR / "update_bundle_icons.py"),
                str(plist), str(car),
            ]):
                raise BrandingError("Branding: failed to update CFBundleIcons")

        # Sync the loose fallback icons in the app root (used by SpringBoard) to
        # the rebuilt catalog, else the home-screen icon stays stale.
        new_extract = workdir / "newextract"
        if _run([str(car_extract), str(car), str(new_extract)],
                stderr=subprocess.DEVNULL):
            _run([
                sys.executable, str(BRANDING_DIR / "overwrite_loose_icons.py"),
                str(appdir), str(new_extract),
            ])

    # --- svgs/: override TwitterAppearance vector glyphs ---
    if have_svgs:
        if not _run([
            sys.executable, str(BRANDING_DIR / "override_appearance_svgs.py"),
            str(appdir), str(svgs_dir),
        ]):
            raise BrandingError("Branding: failed to override TwitterAppearance glyphs")

    # --- root files (e.g. LaunchScreen.nib): overwrite the same file in app root ---
    if have_root:
        for rf in root_files:
            dest = appdir / rf.name
            if dest.exists():
                if dest.is_dir():
                    shutil.rmtree(dest)
                else:
                    dest.unlink()
                shutil.copyfile(rf, dest)
            else:
                err(f"Branding: '{rf.name}' is not present in the app root; skipped.")


def _xcrun_find(tool):
    try:
        out = subprocess.run(
            ["xcrun", "-f", tool], capture_output=True, text=True
        )
    except FileNotFoundError:
        return None
    return out.stdout.strip() if out.returncode == 0 else None


TWITTER_BLUE = (29, 161, 242)


def _paeth(left, above, upper_left):
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    if above_distance <= upper_left_distance:
        return above
    return upper_left


def _write_recolored_rgba_png(source, destination, rgb):
    """Write an 8-bit RGBA PNG with every visible pixel set to `rgb`."""
    raw = Path(source).read_bytes()
    signature = b"\x89PNG\r\n\x1a\n"
    if not raw.startswith(signature):
        raise BrandingError(f"Branding: launch bird is not a PNG: {source}")

    position = len(signature)
    header = None
    compressed = bytearray()
    while position + 12 <= len(raw):
        length = struct.unpack(">I", raw[position:position + 4])[0]
        kind = raw[position + 4:position + 8]
        payload = raw[position + 8:position + 8 + length]
        position += 12 + length
        if kind == b"IHDR":
            header = payload
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break

    if not header or len(header) != 13:
        raise BrandingError("Branding: launch bird PNG has no valid header")
    width, height, depth, color_type, compression, filtering, interlace = (
        struct.unpack(">IIBBBBB", header)
    )
    if (
        depth != 8
        or color_type != 6
        or compression != 0
        or filtering != 0
        or interlace != 0
    ):
        raise BrandingError(
            "Branding: launch bird must be a non-interlaced 8-bit RGBA PNG"
        )

    filtered = zlib.decompress(bytes(compressed))
    stride = width * 4
    expected = height * (stride + 1)
    if len(filtered) != expected:
        raise BrandingError("Branding: launch bird PNG data is truncated")

    previous = bytearray(stride)
    output = bytearray()
    offset = 0
    for _ in range(height):
        filter_kind = filtered[offset]
        scanline = bytearray(filtered[offset + 1:offset + 1 + stride])
        offset += stride + 1
        for index in range(stride):
            left = scanline[index - 4] if index >= 4 else 0
            above = previous[index]
            upper_left = previous[index - 4] if index >= 4 else 0
            if filter_kind == 1:
                predictor = left
            elif filter_kind == 2:
                predictor = above
            elif filter_kind == 3:
                predictor = (left + above) // 2
            elif filter_kind == 4:
                predictor = _paeth(left, above, upper_left)
            elif filter_kind == 0:
                predictor = 0
            else:
                raise BrandingError(
                    f"Branding: unsupported PNG filter {filter_kind}"
                )
            scanline[index] = (scanline[index] + predictor) & 0xFF

        for pixel in range(0, stride, 4):
            scanline[pixel:pixel + 3] = bytes(rgb)
        output.append(0)
        output.extend(scanline)
        previous = scanline

    def chunk(kind, payload):
        checksum = binascii.crc32(kind)
        checksum = binascii.crc32(payload, checksum) & 0xFFFFFFFF
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", checksum)
        )

    destination = Path(destination)
    destination.write_bytes(
        signature
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(output), level=9))
        + chunk(b"IEND", b"")
    )


def _apply_builtin_launch_bird(appdir, workdir):
    """Replace X's pre-injection launch glyph with NeoFreeBird's bird.

    iOS renders LaunchScreen.nib before injected tweak code can execute. X
    12.9's nib requests `xLogo`; redirect that same-length archive string to a
    loose blue bird so the fix does not rebuild or disturb the app's Assets.car.
    """
    nib = appdir / "LaunchScreen.nib"
    bird_directory = (
        BRANDING_DIR.parent
        / "layout"
        / "Library"
        / "Application Support"
        / "BHT"
        / "BHTwitter.bundle"
    )
    birds = {
        # The launch nib has explicit logo bounds (64 points in X 12.24),
        # so these larger textures retain its layout while matching the
        # animation's silhouette and resolution from the first frame.
        "tBird.png": bird_directory / "twitter_bird_launch.png",
        "tBird@2x.png": bird_directory / "twitter_bird_launch@2x.png",
        "tBird@3x.png": bird_directory / "twitter_bird_launch@3x.png",
    }
    if not nib.is_file() or not all(path.is_file() for path in birds.values()):
        return

    archive = nib.read_bytes()
    stock_name = b"xLogo"
    replacement_name = b"tBird"
    if stock_name not in archive:
        return
    if len(stock_name) != len(replacement_name):
        raise BrandingError("Branding: launch image replacement must be same length")
    nib.write_bytes(archive.replace(stock_name, replacement_name))

    for filename, source in birds.items():
        _write_recolored_rgba_png(
            source,
            appdir / filename,
            TWITTER_BLUE,
        )


# --- entry point ------------------------------------------------------------

def apply_ipa_branding(ipa):
    """Unpack the IPA once, apply every enabled step, repackage once."""
    resource_pack = os.environ.get("RESOURCE_PACK", "")
    twitter_branding = os.environ.get("TWITTER_BRANDING", "0") == "1"
    twitter_app_icon = os.environ.get("TWITTER_APP_ICON", "")
    if not resource_pack and not twitter_branding and not twitter_app_icon:
        return

    ipa = Path(ipa)
    if not ipa.is_file():
        raise BrandingError(f"Branding: IPA not found: {ipa}")
    if not _have("unzip"):
        raise BrandingError("Branding: 'unzip' is required")
    if not _have("zip"):
        raise BrandingError("Branding: 'zip' is required")

    workdir = Path(tempfile.mkdtemp())
    try:
        ipa_root = workdir / "ipa"
        if not _run(["unzip", "-q", str(ipa), "-d", str(ipa_root)]):
            raise BrandingError(f"Branding: failed to unpack {ipa}")

        payload = ipa_root / "Payload"
        apps = sorted(payload.glob("*.app")) if payload.is_dir() else []
        appdir = next((a for a in apps if a.is_dir()), None)
        if appdir is None:
            raise BrandingError(f"Branding: could not locate .app inside {ipa}")

        # The built-in launch replacement runs first so an explicitly supplied
        # resource pack can intentionally override it.
        if twitter_branding:
            _apply_builtin_launch_bird(appdir, workdir)
        if resource_pack:
            _apply_resource_pack_to_app(appdir, workdir, resource_pack)
        if twitter_app_icon:
            _install_alternate_icon_in_app(appdir, twitter_app_icon)
        if twitter_branding:
            _set_display_name_in_app(appdir)

        # Repackage the complete extracted root once. `-y` stores symlinks as
        # links instead of following them, while `.` keeps every top-level IPA
        # entry (for example iTunesArtwork) rather than dropping non-Payload
        # metadata.
        ipa = ipa.resolve()
        tmp_ipa = ipa.with_name(ipa.name + ".branding.tmp")
        if tmp_ipa.exists():
            tmp_ipa.unlink()
        if not _run(["zip", "-qry", str(tmp_ipa), "."], cwd=str(ipa_root)):
            if tmp_ipa.exists():
                tmp_ipa.unlink()
            raise BrandingError(f"Branding: failed to repackage {ipa}")
        os.replace(tmp_ipa, ipa)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def main(argv):
    if len(argv) != 2:
        err("usage: ipa_branding.py <ipa_path>")
        return 2
    try:
        apply_ipa_branding(argv[1])
    except BrandingError as exc:
        err(str(exc))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
