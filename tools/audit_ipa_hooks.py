"""Local read-only inventory; does not execute code from the inspected IPA."""
import bisect
import json
import re
import struct
import sys
from pathlib import Path

# TARGET and SOURCE are set by the command-line entry point.

def inventory():
    import macho_metadata as objc
    result = {'images': [], 'classes': {}, 'symbols': {}}
    for path in sorted((TARGET / 'Payload').rglob('*')):
        if not path.is_file():
            continue
        binary = objc.parse_binary(path)
        segments = sorted((int(s.virtual_address), int(s.virtual_address) + int(s.file_size), bytes(s.content)) for s in binary.segments if s.file_size)
        starts = [s[0] for s in segments]
        def mapped(_, addr, size=1):
            n = bisect.bisect_right(starts, addr) - 1
            return n >= 0 and addr + size <= segments[n][1]
        def raw(_, addr, size):
            n = bisect.bisect_right(starts, addr) - 1
            if n < 0:
                raise ValueError(hex(addr))
            s = segments[n]
            off = addr - s[0]
            return s[2][off:off + size]
        def cstring(_, addr, maximum=4096):
            if not addr or not mapped(None, addr):
                return None
            return raw(None, addr, maximum).split(b'\0', 1)[0].decode('utf8', errors='replace')
        def resolve_pointer(_, value):
            if not value:
                return 0
            if mapped(None, value):
                return value
            base = int(binary.imagebase)
            if value >> 63 == 0:
                for target in ((value & ((1 << 36) - 1)) + base, value & ((1 << 36) - 1), (value & ((1 << 43) - 1)) + base):
                    if mapped(None, target):
                        return target
            if (value >> 62) & 1 == 0:
                target = (value & 0xFFFFFFFF) + base if value >> 63 else (value & ((1 << 43) - 1)) + base
                if mapped(None, target):
                    return target
            return 0
        objc.mapped, objc.raw, objc.cstring, objc.resolve_pointer = mapped, raw, cstring, resolve_pointer
        image = path.relative_to(TARGET).as_posix()
        bindings = {int(b.address): b.symbol.name for b in binary.bindings if b.has_symbol}
        for symbol in binary.symbols:
            address = int(symbol.export_info.address) if symbol.has_export_info else int(symbol.value)
            if address:
                result['symbols'].setdefault(symbol.name, []).append([image, address])
        addresses = list(objc.classes(binary) or [])
        names = {a: objc.class_name(binary, a) for a in addresses}
        def bound_class(field):
            sym = bindings.get(field, '')
            return sym.removeprefix('_OBJC_CLASS_$_') if sym.startswith('_OBJC_CLASS_$_') else None
        for addr, name in names.items():
            if not name:
                continue
            superclass = names.get(objc.pointer(binary, addr + 8)) or bound_class(addr + 8)
            methods = {}
            for kind, candidate in [('-', addr), ('+', objc.pointer(binary, addr))]:
                if not mapped(None, candidate, 40):
                    continue
                for selector, types, imp in objc.methods_for_class(binary, candidate):
                    if selector:
                        methods[kind + selector] = {'types': types, 'address': imp}
            ro = objc.class_ro(binary, addr)
            # A category in an earlier image may extend a class defined in a
            # later image. Preserve those methods when loading its class body.
            previous_methods = result['classes'].get(name, {}).get('methods', {})
            result['classes'][name] = {'image': image, 'superclass': superclass, 'size': objc.u32(binary, ro + 8), 'methods': {**previous_methods, **methods}}
        for section in binary.sections:
            if section.name not in ('__objc_catlist', '__objc_nlcatlist'):
                continue
            for off in range(0, section.size, 8):
                cat = objc.pointer(binary, section.virtual_address + off)
                if not mapped(None, cat, 48):
                    continue
                name = names.get(objc.pointer(binary, cat + 8)) or bound_class(cat + 8)
                if not name:
                    continue
                entry = result['classes'].setdefault(name, {'image': image, 'superclass': None, 'category_only': True, 'methods': {}})
                for kind, field in [('-', 16), ('+', 24)]:
                    for sel, types, imp in objc.method_list(binary, objc.pointer(binary, cat + field)) or []:
                        if sel:
                            entry['methods'][kind + sel] = {'types': types, 'address': imp}
        cryptids = [int(c.crypt_id) for c in binary.commands if hasattr(c, 'crypt_id')]
        result['images'].append({'image': image, 'classes': len(names), 'cryptids': cryptids, 'uuid': str(binary.uuid.uuid) if binary.has_uuid else None})
    return result

def hooks(inv):
    output = []
    system = ('UI', 'NS', 'AV', 'WK', 'CA', 'SF', 'PH')
    inherited_system = {
        'UIView': {'-didMoveToWindow', '-layoutSubviews', '-didAddSubview:',
                   '-traitCollectionDidChange:', '-setHidden:', '-setAlpha:', '-sizeThatFits:'},
        'UIViewController': {'-viewDidLoad', '-viewWillAppear:', '-viewDidAppear:',
                             '-viewWillDisappear:', '-viewDidDisappear:',
                             '-viewDidLayoutSubviews', '-traitCollectionDidChange:'},
        'CALayer': {'-setHidden:', '-setOpacity:'},
        'NSObject': {'-init', '-dealloc', '-description', '-hash', '-isEqual:'},
    }
    def lookup(name, key, seen=None):
        seen = (seen or set()) | {name}
        entry = inv['classes'].get(name, {})
        if key in entry.get('methods', {}):
            return name, entry['methods'][key]
        parent = entry.get('superclass')
        if parent and parent not in seen:
            return lookup(parent, key, seen)
        return name, None
    for path in sorted((SOURCE / 'src' / 'Hooks').glob('*.x')):
        source = path.read_text(encoding='utf8')
        # Preserve lines while discarding comments; %new methods are additions.
        source = re.sub(r'/\*.*?\*/|//[^\n]*', lambda m: '\n' * m[0].count('\n'), source, flags=re.S)
        for block in re.finditer(r'%hook\s+(\w+)(.*?)(?=%end)', source, re.S):
            name, body = block.groups()
            last = 0
            for method in re.finditer(r'^\s*([+-])\s*\(([^)]+)\)\s*([^;{}]+)\{', body, re.M):
                sign, ret, args = method.groups()
                names = re.findall(r'(\w+)\s*:', args)
                sel = ':'.join(names) + ':' if names else args.strip()
                is_new = '%new' in body[last:method.start()]
                last = method.end()
                owner, native = lookup(name, sign + sel)
                # Reaching NSObject/UIViewController does not make an unknown
                # app-specific selector a system method. This previously hid
                # the removed Activity History segmented-controller hooks.
                system_method = ((name not in inv['classes'] or inv['classes'][name].get('category_only')) and name.startswith(system)) or sign + sel in inherited_system.get(owner, set())
                status = 'new' if is_new else 'present' if native else 'system-runtime' if system_method else 'missing-method' if name in inv['classes'] else 'missing-class'
                output.append({'file': path.relative_to(SOURCE).as_posix(), 'class': name, 'selector': sign + sel, 'return': ret, 'args': args.strip(), 'status': status, 'owner': owner, 'native': native})
    return output

def main():
    import argparse, hashlib, plistlib, tempfile, zipfile
    from collections import Counter
    global TARGET, SOURCE
    parser = argparse.ArgumentParser(description="Audit Logos hooks against an IPA's Objective-C metadata. Requires lief. No app code is executed.")
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    SOURCE = args.source.resolve()
    with tempfile.TemporaryDirectory(prefix="nfb-hook-audit-") as directory:
        TARGET = Path(directory)
        with zipfile.ZipFile(args.ipa) as archive:
            plist = next(n for n in archive.namelist() if n.startswith("Payload/") and n.count("/") == 2 and n.endswith("/Info.plist"))
            metadata = plistlib.loads(archive.read(plist))
            for info in archive.infolist():
                if info.is_dir(): continue
                with archive.open(info) as stream:
                    magic = stream.read(4)
                if magic not in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"): continue
                path = (TARGET / info.filename).resolve()
                if TARGET.resolve() not in path.parents: raise ValueError("Unsafe archive path")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(archive.read(info))
        data = inventory()
        entries = hooks(data)
        for entry in entries:
            if entry["class"] == "HomeTimelineContainerViewController" and entry["status"] == "missing-class":
                entry["status"] = "guarded-legacy-alias"
            # These explicitly optional implementations have constructor
            # guards in the named source files. Keep absence visible instead
            # of reporting them as present/inherited methods.
            optional_guards = {
                ("src/Hooks/Profile.x", "T1ProfileHeaderViewController", "-actionButtonProviders"):
                    "BHTLegacyProfileActionProviders",
                ("src/Hooks/ReplyNetworkDiagnostics.x", "TNLURLSessionTaskOperation",
                 "-_network_finalizeDidCompleteTask:URLSession:error:"):
                    "BHTNativeReplyTNLCompletionHooks",
            }
            guard = optional_guards.get((entry["file"], entry["class"], entry["selector"]))
            if guard and entry["status"] == "missing-method":
                source = (SOURCE / entry["file"]).read_text(encoding="utf8")
                if f"%group {guard}" in source and f"%init({guard})" in source:
                    entry.update(status="guarded-runtime-alternative", runtime_guard=guard)
        # Pure Swift names may have zero nlist values and live in the export
        # trie. Include the resolved addresses of each live sidebar setter.
        swift = {name: values for name, values in data["symbols"].items()
                 if "TwitterDash0B10DataSourceC" in name and "ItemsSay" in name and name.endswith("Gvs")}
        probes = []
        aliases = {}
        for name in data["classes"]:
            match = re.match(r"_TtC(\d+)", name)
            if match:
                i = match.end(); size = int(match[1]); module = name[i:i+size]; i += size
                match = re.match(r"(\d+)(.*)", name[i:])
                if match and len(match[2]) == int(match[1]): aliases[module + "." + match[2]] = name
        reporter = (SOURCE / "src/Compatibility/BHTCompatibilityReporter.m").read_text(encoding="utf8")
        for feature, name, selector, is_class in re.findall(r'BHTProbe\(@"([^"]+)",\s*@"([^"]+)",\s*@"([^"]+)",\s*(YES|NO)\)', reporter):
            lookup = aliases.get(name, name)
            method = ("+" if is_class == "YES" else "-") + selector
            seen = set(); native = None
            while lookup and lookup not in seen:
                seen.add(lookup)
                cls = data["classes"].get(lookup, {})
                native = cls.get("methods", {}).get(method)
                if native: break
                lookup = cls.get("superclass")
            probes.append({"feature":feature,"class":name,"selector":method,"native":native})
        report = {"host": {k: metadata.get(k) for k in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "MinimumOSVersion")},
                  "ipa_sha256": hashlib.file_digest(args.ipa.open("rb"), "sha256").hexdigest(),
                  "images": data["images"], "counts": dict(Counter(e["status"] for e in entries)),
                  "hooks": entries, "sidebar_swift_setters": swift, "runtime_probes": probes,
                  "limitations": "Metadata presence is not device execution. System framework hooks and dynamic theme providers require runtime checks. Legacy aliases and alternative probes may deliberately be absent."}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2), encoding="utf8")
        print(json.dumps({"host": report["host"], "images": len(data["images"]), "hooks": report["counts"], "sidebar_setters": len(swift)}, indent=2))
        if any(e["status"].startswith("missing") for e in entries): raise SystemExit(1)
        if any(any(image["cryptids"]) for image in data["images"]): raise SystemExit("Encrypted executable")

if __name__ == "__main__":
    main()
