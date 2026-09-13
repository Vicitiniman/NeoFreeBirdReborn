#!/usr/bin/env python3
"""Combine an audited local IPA with a compiled sideload payload.

Requires lief and Pillow. Produces an unsigned IPA for the user's sideload
signer; does not upload the host app or execute any of its code.
"""
import argparse
import hashlib
import json
import plistlib
import shutil
import stat
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

import lief
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "branding"))
import ipa_branding as branding

LIBRARIES = ("libsubstrate.dylib", "zxPluginsInject.dylib", "libbhFLEX.dylib", "BHTwitter.dylib")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def patch_binary(path, *, inject=False):
    parsed = lief.MachO.parse(str(path))
    if not parsed or len(parsed) != 1:
        raise ValueError(f"Expected one arm64 image: {path.name}")
    binary = parsed.at(0)
    if binary.header.cpu_type != lief.MachO.Header.CPU_TYPE.ARM64:
        raise ValueError(f"Expected arm64: {path.name}")
    if any(getattr(command, "crypt_id", 0) for command in binary.commands):
        raise ValueError(f"Encrypted image: {path.name}")
    original_text = {s.name: bytes(s.content) for s in binary.sections if s.name == "__text"}
    original_signature = bytes(binary.code_signature.content) if inject and binary.has_code_signature else None
    for library in binary.libraries:
        if library.command == lief.MachO.LoadCommand.TYPE.ID_DYLIB:
            library.name = "@rpath/" + path.name
        elif "CydiaSubstrate.framework/CydiaSubstrate" in library.name or library.name.endswith("/libsubstrate.dylib"):
            library.name = "@rpath/libsubstrate.dylib"
    if inject:
        existing = {library.name for library in binary.libraries}
        for name in LIBRARIES:
            dependency = "@executable_path/Frameworks/" + name
            if dependency not in existing:
                binary.add_library(dependency)
    # Retain the host's signature blob as an entitlement source for the user's
    # signer. Its hashes are stale after injection and must be regenerated.
    if not inject:
        binary.remove_signature()
    binary.write(str(path))
    check = lief.MachO.parse(str(path))
    success, error = lief.MachO.check_layout(check)
    if not success:
        raise ValueError(f"Invalid Mach-O layout for {path.name}: {error}")
    if original_signature is not None and (
        not check.at(0).has_code_signature or bytes(check.at(0).code_signature.content) != original_signature
    ):
        raise ValueError("The original host entitlement/signature blob was not preserved")
    for section in check.at(0).sections:
        if section.name in original_text and bytes(section.content) != original_text[section.name]:
            raise ValueError(f"Executable instructions changed in {path.name}")
    return [library.name for library in check.at(0).libraries]


def resize_icon(source, size, destination):
    with Image.open(source) as image:
        image.convert("RGB").resize((size, size), Image.Resampling.LANCZOS).save(destination)


def safe_extract(archive, info, root):
    destination = (root / info.filename).resolve()
    if root.resolve() not in destination.parents:
        raise ValueError("Unsafe archive path")
    if stat.S_ISLNK(info.external_attr >> 16):
        raise ValueError("Payload inputs must contain regular files")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(archive.read(info))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("payload", type=Path, help="NeoFreeBird-sideload-payload.zip from Actions")
    parser.add_argument("--substrate", type=Path, required=True, help="Authorized arm64 hook runtime exporting MSHookMessageEx and MSHookFunction")
    parser.add_argument("--audit", type=Path, default=ROOT / "docs/X12_24_1_HOOK_AUDIT.json")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve() == args.ipa.resolve() or args.output.exists():
        raise ValueError("Choose a new output path; the source IPA is never overwritten")
    audit = json.loads(args.audit.read_text(encoding="utf8"))
    if digest(args.ipa) != audit["ipa_sha256"]:
        raise ValueError("The IPA does not match the binary used for the hook audit")
    substrate = lief.MachO.parse(str(args.substrate))
    exported = {symbol.name for symbol in substrate.at(0).symbols if symbol.value or symbol.has_export_info}
    if not {"_MSHookFunction", "_MSHookMessageEx"}.issubset(exported):
        raise ValueError("The supplied hook runtime is missing required exports")
    report = {"source_ipa_sha256": digest(args.ipa), "payload_sha256": digest(args.payload),
              "substrate_sha256": digest(args.substrate), "signing": "Unsigned; resign with a sideloading tool", "libraries": {}}
    with tempfile.TemporaryDirectory(prefix="nfb-local-ipa-") as directory:
        work = Path(directory)
        with zipfile.ZipFile(args.ipa) as source:
            info_name = next(n for n in source.namelist() if n.startswith("Payload/") and n.count("/") == 2 and n.endswith("/Info.plist"))
            info = plistlib.loads(source.read(info_name))
            if (info.get("CFBundleIdentifier"), info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != ("com.atebits.Tweetie2", "12.24.1", "1"):
                raise ValueError("Expected X 12.24.1 build 1")
            app_prefix = str(PurePosixPath(info_name).parent) + "/"
            app = work / app_prefix
            executable = app_prefix + info["CFBundleExecutable"]
            # Extract only files we edit. Every other archive member is streamed
            # unchanged, retaining its ZIP attributes (including symbolic links).
            for member in source.infolist():
                relative = member.filename.removeprefix(app_prefix)
                if member.filename in (info_name, executable, app_prefix + "LaunchScreen.nib") or (
                    member.filename.startswith(app_prefix) and relative.count("/") == 1 and relative.endswith(".lproj/InfoPlist.strings")):
                    safe_extract(source, member, work)
            with zipfile.ZipFile(args.payload) as payload:
                for member in payload.infolist():
                    if member.is_dir(): continue
                    if not member.filename.startswith("SideloadPayload/"):
                        raise ValueError("Unexpected payload archive entry")
                    relative_name = member.filename.removeprefix("SideloadPayload/")
                    data = payload.read(member)
                    target = (app / relative_name).resolve()
                    if app.resolve() not in target.parents: raise ValueError("Unsafe payload path")
                    if stat.S_ISLNK(member.external_attr >> 16): raise ValueError("Unexpected payload symlink")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(data)
            frameworks = app / "Frameworks"
            shutil.copyfile(args.substrate, frameworks / "libsubstrate.dylib")
            for name in LIBRARIES:
                library = frameworks / name
                if not library.is_file(): raise ValueError(f"Missing payload library: {name}")
                report["libraries"][name] = patch_binary(library)
            report["main_dependencies"] = patch_binary(work / executable, inject=True)
            branding._resize_icon = resize_icon
            branding._apply_builtin_launch_bird(app, work)
            branding._install_alternate_icon_in_app(app, ROOT / "branding/TwitterAppIcon.png")
            branding._set_display_name_in_app(app)
            info = plistlib.loads((app / "Info.plist").read_bytes())
            info.pop("UISupportedDevices", None)
            (app / "Info.plist").write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            replacements = {p.relative_to(work).as_posix(): p for p in app.rglob("*") if p.is_file()}
            args.output.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as output:
                for member in source.infolist():
                    if member.filename in replacements: continue
                    if member.filename == app_prefix + "embedded.mobileprovision" or member.filename.startswith((app_prefix + "_CodeSignature/", app_prefix + "Watch/")): continue
                    with source.open(member) as incoming, output.open(member, "w") as outgoing:
                        shutil.copyfileobj(incoming, outgoing, length=1024 * 1024)
                for name, path in replacements.items():
                    member = zipfile.ZipInfo(name)
                    member.compress_type = zipfile.ZIP_DEFLATED
                    member.create_system = 3
                    mode = 0o755 if name == executable or name.endswith(".dylib") else 0o644
                    member.external_attr = (stat.S_IFREG | mode) << 16
                    output.writestr(member, path.read_bytes())
        with zipfile.ZipFile(args.output) as result:
            if result.testzip() is not None: raise ValueError("Output archive CRC check failed")
            if len(result.namelist()) != len(set(result.namelist())): raise ValueError("Duplicate archive entries")
            if not any(n.startswith(app_prefix + "BHTwitter.bundle/") for n in result.namelist()): raise ValueError("Missing settings resources")
        report["output_sha256"] = digest(args.output)
        report["output_bytes"] = args.output.stat().st_size
        report["host_version"] = "12.24.1 (1)"
        args.output.with_suffix(".package.json").write_text(json.dumps(report, indent=2), encoding="utf8")
        print(json.dumps({"output": str(args.output.resolve()), "bytes": report["output_bytes"], "sha256": report["output_sha256"]}, indent=2))


if __name__ == "__main__":
    main()
