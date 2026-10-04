#!/usr/bin/env python3
"""
Static dump of an iOS .ipa or a raw Mach-O.

No execution. No device. No debugger. Reads bytes and reports what is in them:
Mach-O header, load commands, linked frameworks, segments and sections, symbol
table, Objective-C metadata, Swift types, and every string worth reading.

    python static_dump.py path/to/JET.ipa
"""

import hashlib
import plistlib
import re
import struct
import sys
import zipfile
from collections import Counter, OrderedDict

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

CPU_TYPES = {0x0100000C: "arm64", 0x0000000C: "arm", 0x01000007: "x86_64", 0x00000007: "i386"}
FILE_TYPES = {1: "MH_OBJECT", 2: "MH_EXECUTE", 6: "MH_DYLIB", 8: "MH_BUNDLE"}

FLAGS = OrderedDict([
    (0x1, "NOUNDEFS"), (0x2, "INCRLINK"), (0x4, "DYLDLINK"), (0x8, "BINDATLOAD"),
    (0x10, "PREBOUND"), (0x20, "SPLIT_SEGS"), (0x40, "LAZY_INIT"), (0x80, "TWOLEVEL"),
    (0x100, "FORCE_FLAT"), (0x200, "NOMULTIDEFS"), (0x400, "NOFIXPREBINDING"),
    (0x800, "PREBINDABLE"), (0x1000, "ALLMODSBOUND"), (0x2000, "SUBSECTIONS_VIA_SYMBOLS"),
    (0x4000, "CANONICAL"), (0x8000, "WEAK_DEFINES"), (0x10000, "BINDS_TO_WEAK"),
    (0x20000, "ALLOW_STACK_EXECUTION"), (0x40000, "ROOT_SAFE"), (0x80000, "SETUID_SAFE"),
    (0x100000, "NO_REEXPORTED_DYLIBS"), (0x200000, "PIE"), (0x400000, "DEAD_STRIPPABLE_DYLIB"),
    (0x800000, "HAS_TLV_DESCRIPTORS"), (0x1000000, "NO_HEAP_EXECUTION"),
])

PLATFORMS = {1: "macOS", 2: "iOS", 3: "tvOS", 4: "watchOS", 5: "bridgeOS", 6: "macCatalyst", 7: "iOSSimulator"}

LC = {
    0x1: "LC_SEGMENT", 0x2: "LC_SYMTAB", 0x3: "LC_SYMSEG", 0x4: "LC_THREAD",
    0xB: "LC_DYSYMTAB", 0xC: "LC_LOAD_DYLIB", 0xD: "LC_ID_DYLIB", 0xE: "LC_LOAD_DYLINKER",
    0xF: "LC_ID_DYLINKER", 0x1B: "LC_UUID", 0x1C: "LC_RPATH", 0x1D: "LC_CODE_SIGNATURE",
    0x19: "LC_SEGMENT_64", 0x1A: "LC_ROUTINES_64", 0x21: "LC_DYLD_INFO",
    0x22: "LC_DYLD_INFO_ONLY", 0x25: "LC_VERSION_MIN_IPHONEOS", 0x26: "LC_FUNCTION_STARTS",
    0x27: "LC_DYLD_ENVIRONMENT", 0x29: "LC_DATA_IN_CODE", 0x2A: "LC_SOURCE_VERSION",
    0x2B: "LC_DYLIB_CODE_SIGN_DRS", 0x2C: "LC_ENCRYPTION_INFO", 0x2E: "LC_LINKER_OPTION",
    0x2F: "LC_LINKER_OPTIMIZATION_HINT", 0x32: "LC_BUILD_VERSION", 0x33: "LC_DYLD_EXPORTS_TRIE",
    0x34: "LC_DYLD_CHAINED_FIXUPS", 0x80000022: "LC_DYLD_INFO_ONLY|REQ",
    0x80000028: "LC_MAIN|REQ", 0x80000034: "LC_DYLD_CHAINED_FIXUPS|REQ",
}

N_TYPE = {0x0: "UNDF", 0x1: "ABS", 0xE: "SECT", 0x2: "PBUD", 0xC: "INDR"}

SWIFT_KIND = {
    "C": "class", "V": "struct", "O": "enum", "P": "protocol", "F": "function",
    "f": "function", "M": "method", "v": "variable", "Z": "extension", "T": "typealias",
    "S": "typealias", "a": "accessor", "i": "init", "c": "init", "W": "witness",
    "e": "field", "D": "deinit", "U": "unknown",
}


def hx(n):
    return f"0x{n:x}"


# ----------------------------------------------------------------------------
# Mach-O parsing
# ----------------------------------------------------------------------------

class MachO:
    def __init__(self, blob, label="binary"):
        self.blob = blob
        self.label = label
        self.sections = []          # list of dicts
        self.section_data = {}      # (seg, sect) -> bytes
        self.dylibs = []
        self.rpaths = []
        self.uuid = None
        self.min_os = None
        self.sdk = None
        self.platform = None
        self.symtab = None
        self.symbols = []
        self.encryption = None
        self.flags = 0
        self.header = {}
        self._parse()

    def _parse(self):
        blob = self.blob
        magic = struct.unpack_from("<I", blob, 0)[0]

        if magic in (FAT_MAGIC, FAT_MAGIC_64):
            is64 = magic == FAT_MAGIC_64
            nfat = struct.unpack_from(">I", blob, 4)[0]
            best = None
            for i in range(nfat):
                off = 8 + i * (32 if is64 else 20)
                cputype = struct.unpack_from(">I", blob, off)[0]
                foff, fsize = struct.unpack_from(">II", blob, off + 8)
                if cputype == 0x0100000C:
                    best = (foff, fsize)
            if best is None:
                _, foff, fsize = struct.unpack_from(">III", blob, 8 + 8)
                best = (foff, fsize)
            self.slice_offset, slice_size = best
            blob = blob[best[0]:best[0] + best[1]]
            self.blob = blob
            magic = struct.unpack_from("<I", blob, 0)[0]

        if magic != MH_MAGIC_64:
            raise ValueError(f"not a 64-bit little-endian Mach-O (magic {hx(magic)})")

        (_, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, _res) = struct.unpack_from("<IIIIIIII", blob, 0)
        self.header = {
            "cputype": cputype, "cpusubtype": cpusub & 0xFFFFFF, "filetype": ftype,
            "ncmds": ncmds, "sizeofcmds": sizeofcmds, "flags": flags,
        }
        self.flags = flags

        offset = 32
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", blob, offset)
            self._load_command(cmd, cmdsize, offset)
            offset += cmdsize

    def _load_command(self, cmd, cmdsize, offset):
        blob = self.blob
        base = cmd & ~0x80000000

        if base == 0x19:  # LC_SEGMENT_64
            segname = blob[offset + 8:offset + 24].rstrip(b"\0").decode("utf-8", "replace")
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", blob, offset + 24)
            maxprot, initprot, nsects, _flags = struct.unpack_from("<IIII", blob, offset + 56)
            soff = offset + 72
            for _ in range(nsects):
                sectname = blob[soff:soff + 16].rstrip(b"\0").decode("utf-8", "replace")
                ssegname = blob[soff + 16:soff + 32].rstrip(b"\0").decode("utf-8", "replace")
                addr, size, sfileoff = struct.unpack_from("<QQI", blob, soff + 32)
                self.sections.append({
                    "seg": ssegname or segname, "sect": sectname, "addr": addr,
                    "size": size, "offset": sfileoff,
                })
                if sfileoff and size:
                    self.section_data[(ssegname or segname, sectname)] = blob[sfileoff:sfileoff + size]
                soff += 80

        elif base == 0xC or base == 0xD:  # LC_LOAD_DYLIB / LC_ID_DYLIB
            nameoff = struct.unpack_from("<I", blob, offset + 8)[0]
            name = blob[offset + nameoff:offset + cmdsize].split(b"\0")[0].decode("utf-8", "replace")
            if base == 0xC:
                self.dylibs.append(name)

        elif base == 0x1C:  # LC_RPATH
            nameoff = struct.unpack_from("<I", blob, offset + 8)[0]
            path = blob[offset + nameoff:offset + cmdsize].split(b"\0")[0].decode("utf-8", "replace")
            self.rpaths.append(path)

        elif base == 0x1B:  # LC_UUID
            raw = blob[offset + 8:offset + 24]
            self.uuid = "-".join([raw[:4].hex(), raw[4:6].hex(), raw[6:8].hex(),
                                  raw[8:10].hex(), raw[10:].hex()]).upper()

        elif base == 0x32:  # LC_BUILD_VERSION
            platform, minos, sdk, _ntools = struct.unpack_from("<IIII", blob, offset + 8)
            self.platform = PLATFORMS.get(platform, str(platform))
            self.min_os = decode_version(minos)
            self.sdk = decode_version(sdk)

        elif base == 0x25:  # LC_VERSION_MIN_IPHONEOS
            version, sdk = struct.unpack_from("<II", blob, offset + 8)
            self.platform = "iOS"
            self.min_os = decode_version(version)
            self.sdk = decode_version(sdk)

        elif base == 0x2:  # LC_SYMTAB
            symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", blob, offset + 8)
            self.symtab = {"symoff": symoff, "nsyms": nsyms, "stroff": stroff, "strsize": strsize}
            self._read_symbols()

        elif base == 0x2C:  # LC_ENCRYPTION_INFO
            cryptoff, cryptsize, cryptid = struct.unpack_from("<III", blob, offset + 8)
            self.encryption = {"cryptid": cryptid, "cryptsize": cryptsize}

    def _read_symbols(self):
        blob = self.blob
        st = self.symtab
        for i in range(st["nsyms"]):
            off = st["symoff"] + i * 16
            if off + 16 > len(blob):
                break
            n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from("<IBBHQ", blob, off)
            stroff = st["stroff"] + n_strx
            end = blob.find(b"\0", stroff)
            if end < 0:
                continue
            name = blob[stroff:end].decode("utf-8", "replace")
            if not name:
                continue
            kind = n_type & 0x0E
            self.symbols.append({
                "name": name, "type": N_TYPE.get(kind, hx(kind)),
                "external": bool(n_type & 0x01), "sect": n_sect, "value": n_value,
            })


def decode_version(v):
    return f"{(v >> 16) & 0xFFFF}.{(v >> 8) & 0xFF}.{v & 0xFF}"


def printable_strings(data, minlen=6):
    pattern = re.compile(rb"[\x20-\x7e]{%d,}" % minlen)
    return [m.group().decode("ascii") for m in pattern.finditer(data)]


def swift_unmangle(sym):
    """Enough of the Swift mangling scheme to make symbols readable."""
    if not sym.startswith("$s"):
        return None
    body = sym[2:]
    parts = []
    i = 0
    while i < len(body):
        m = re.match(r"(\d+)", body[i:])
        if m:
            length = int(m.group(1))
            start = i + len(m.group(1))
            chunk = body[start:start + length]
            if chunk.isprintable() and chunk:
                parts.append(chunk)
            i = start + length
            continue
        ch = body[i]
        label = SWIFT_KIND.get(ch)
        if label and parts:
            parts.append(f"<{label}>")
        i += 1
    return ".".join(p for p in parts if not p.startswith("<")) or None


# ----------------------------------------------------------------------------
# reporting
# ----------------------------------------------------------------------------

def rule(title):
    print()
    print("=" * 74)
    print(f"  {title}")
    print("=" * 74)


def load_binary(path):
    if path.lower().endswith(".ipa") or zipfile.is_zipfile(path):
        z = zipfile.ZipFile(path)
        names = z.namelist()
        app_dirs = sorted({n.split("/")[1] for n in names if n.startswith("Payload/") and len(n.split("/")) > 2})
        if not app_dirs:
            raise SystemExit("no Payload/*.app in that ipa")
        app = app_dirs[0]
        info = plistlib.loads(z.read(f"Payload/{app}/Info.plist"))
        exe = info.get("CFBundleExecutable", app.rsplit(".", 1)[0])
        binary = z.read(f"Payload/{app}/{exe}")
        extra = {
            "app": app, "names": names, "exe": exe, "info": info, "zip": z,
            "signed": any("_CodeSignature" in n for n in names),
            "provision": any(n.endswith("embedded.mobileprovision") for n in names),
        }
        return binary, extra
    with open(path, "rb") as fh:
        return fh.read(), {"app": None, "names": [], "exe": None, "info": None, "zip": None,
                           "signed": False, "provision": False}


def main(path):
    with open(path, "rb") as fh:
        filehash = hashlib.sha256(fh.read()).hexdigest()

    blob, meta = load_binary(path)
    macho = MachO(blob, path)

    print(f"target      : {path}")
    print(f"sha256      : {filehash}")
    print(f"size        : {len(blob):,} bytes")

    # ---------------------------------------------------------------- container
    if meta["info"]:
        rule("CONTAINER")
        print(f"app bundle  : Payload/{meta['app']}")
        print(f"executable  : {meta['exe']}")
        print(f"code sig    : {'present' if meta['signed'] else 'ABSENT (unsigned)'}")
        print(f"provisioning: {'present' if meta['provision'] else 'ABSENT'}")
        print()
        for key in ("CFBundleIdentifier", "CFBundleName", "CFBundleShortVersionString",
                    "CFBundleVersion", "MinimumOSVersion", "DTPlatformName", "DTSDKName"):
            if key in meta["info"]:
                print(f"  {key:28} {meta['info'][key]}")
        print()
        print("  payload entries:")
        for n in sorted(meta["names"]):
            if n.endswith("/"):
                continue
            info = meta["zip"].getinfo(n)
            print(f"    {info.file_size:>10,}  {n}")

        rule("PRIVACY STRINGS AS SHIPPED")
        for key, value in sorted(meta["info"].items()):
            if key.startswith("NS") and "Usage" in key:
                print(f"  {key}")
                print(f"      {value}")

    # ------------------------------------------------------------------- header
    rule("MACH-O HEADER")
    h = macho.header
    print(f"magic        : 0xFEEDFACF (64-bit Mach-O, little endian)")
    print(f"cputype      : {h['cputype']:#x}  ({CPU_TYPES.get(h['cputype'], 'unknown')})")
    print(f"cpusubtype   : {h['cpusubtype']}")
    print(f"filetype     : {h['filetype']}  ({FILE_TYPES.get(h['filetype'], '?')})")
    print(f"ncmds        : {h['ncmds']}")
    print(f"sizeofcmds   : {h['sizeofcmds']:,} bytes")
    print(f"flags        : {hx(macho.flags)}")
    for bit, name in FLAGS.items():
        if macho.flags & bit:
            print(f"                 {name}")
    print(f"platform     : {macho.platform}")
    print(f"min os       : {macho.min_os}")
    print(f"sdk          : {macho.sdk}")
    print(f"uuid         : {macho.uuid}")

    if macho.encryption:
        state = "PLAINTEXT (cryptid 0)" if macho.encryption["cryptid"] == 0 else "ENCRYPTED (FairPlay)"
        print(f"encryption   : {state}")

    pie = "yes" if macho.flags & 0x200000 else "NO — not position independent"
    heap_exec = "yes" if macho.flags & 0x1000000 else "no"
    print(f"PIE          : {pie}")
    print(f"heap exec    : {heap_exec}")

    # ----------------------------------------------------------------- segments
    rule("SEGMENTS AND SECTIONS")
    print(f"{'segment':<18}{'section':<22}{'address':>14}{'size':>12}")
    print("-" * 74)
    for s in macho.sections:
        print(f"{s['seg']:<18}{s['sect']:<22}{hx(s['addr']):>14}{s['size']:>12,}")

    # ------------------------------------------------------------------ dylibs
    rule("LINKED FRAMEWORKS AND LIBRARIES")
    system = [d for d in macho.dylibs if d.startswith("/System/Library")]
    others = [d for d in macho.dylibs if not d.startswith("/System/Library")]
    for d in sorted(others):
        print(f"  [third-party] {d}")
    for d in sorted(system):
        print(f"  {d.split('/')[-1]:<34} {d}")
    if macho.rpaths:
        print()
        for r in macho.rpaths:
            print(f"  rpath: {r}")

    # ----------------------------------------------------------------- symbols
    rule("SYMBOL TABLE")
    defined = [s for s in macho.symbols if s["type"] != "UNDF"]
    imported = [s for s in macho.symbols if s["type"] == "UNDF"]
    print(f"total symbols : {len(macho.symbols)}")
    print(f"defined       : {len(defined)}")
    print(f"imported      : {len(imported)}")

    swift_syms = [s for s in macho.symbols if s["name"].startswith("$s")]
    objc_syms = [s for s in macho.symbols if s["name"].startswith("_OBJC_")]
    print(f"swift         : {len(swift_syms)}")
    print(f"objc          : {len(objc_syms)}")

    if swift_syms:
        rule("SWIFT SYMBOLS (demangled where possible)")
        seen = set()
        for s in swift_syms:
            readable = swift_unmangle(s["name"])
            if readable and readable not in seen:
                seen.add(readable)
                print(f"  {readable}")
        print(f"\n  ({len(seen)} unique readable names from {len(swift_syms)} raw symbols)")
        print("\n  raw samples:")
        for s in swift_syms[:8]:
            print(f"    {s['name'][:96]}")

    # --------------------------------------------------------------- objc meta
    rule("OBJECTIVE-C METADATA")
    classes = set()
    selectors = set()
    for key in (("__TEXT", "__objc_classname"), ("__DATA", "__objc_classname"),
                ("__DATA_CONST", "__objc_classname")):
        for text in printable_strings(macho.section_data.get(key, b""), 3):
            classes.add(text)
    for key in (("__TEXT", "__objc_methname"), ("__DATA", "__objc_methname"),
                ("__DATA_CONST", "__objc_methname")):
        for text in printable_strings(macho.section_data.get(key, b""), 3):
            selectors.add(text)

    print(f"class names : {len(classes)}")
    for c in sorted(classes)[:40]:
        print(f"    {c}")
    print(f"selectors   : {len(selectors)}")
    for s in sorted(selectors)[:30]:
        print(f"    {s}")

    # ---------------------------------------------------------------- strings
    rule("INTERESTING STRINGS")

    everything = b"\n".join(macho.section_data.values()) or blob
    strings = printable_strings(everything, 6)
    pool = set(strings)

    findings = OrderedDict()

    uuid_re = re.compile(r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")
    host_re = re.compile(r"^[a-z0-9][a-z0-9.-]*\.(com|net|org|io|dev|app|co|az|ru|cn)$", re.I)
    path_re = re.compile(r"^/(Users|home|var|private|Applications)/")

    buckets = {
        "GATT UUIDs": lambda s: uuid_re.match(s),
        "URLs and hosts": lambda s: s.startswith(("http://", "https://", "ws://", "wss://")),
        "domains": lambda s: host_re.match(s) and " " not in s,
        "build paths (leak the builder)": lambda s: path_re.match(s),
        "keys / secrets / tokens": lambda s: re.search(
            r"(?i)(secret|api[_-]?key|apikey|token|password|passwd|credential|private[_-]?key|hmac|salt)", s),
        "our own identifiers": lambda s: "SK-" in s or "JET" in s or "jet-" in s,
    }

    for label, test in buckets.items():
        hits = sorted({s for s in pool if test(s)})
        if hits:
            findings[label] = hits

    for label, hits in findings.items():
        print(f"\n  -- {label} ({len(hits)}) --")
        for s in hits[:30]:
            print(f"     {s}")
        if len(hits) > 30:
            print(f"     … and {len(hits) - 30} more")

    # ------------------------------------------------------ targeted hunt
    rule("TARGETED HUNT: does this binary carry a usable fleet key?")

    candidates = [
        "jet-demo-fleet-key-v1",
        "FLEET_SECRET",
        "fleetKey",
        "sharedSecret",
        "6a4e0001-9f3b-4c2a-8e11-71d0a5c9b120",
        "6A4E0001",
        "jet:",
    ]
    for c in candidates:
        where = []
        if c.encode() in blob:
            where.append("raw bytes")
        if any(c.lower() in s.lower() for s in pool):
            where.append("string table")
        verdict = ", ".join(where) if where else "not found"
        print(f"  {c:<46} {verdict}")

    print()
    print("  How the unlock key is actually handled:")
    print("    the app stores SHA256('jet-demo-fleet-key-v1') at runtime — the")
    print("    seed string above is what a static dump recovers. in a production")
    print("    build that literal does not exist in the app at all, because the")
    print("    HMAC is computed server-side and only the signature travels.")

    # ----------------------------------------------------------------- entropy
    rule("SECTION ENTROPY (packing / encryption check)")
    import math
    for s in macho.sections:
        data = macho.section_data.get((s["seg"], s["sect"]))
        if not data or len(data) < 256:
            continue
        counts = Counter(data)
        total = len(data)
        entropy = -sum((c / total) * math.log2(c / total) for c in counts.values())
        bar = "#" * int(entropy * 4)
        print(f"  {s['seg']},{s['sect']:<24} {len(data):>9,}B  {entropy:5.2f}  {bar}")

    print()
    print("  (7.9+ on a large section usually means packed or encrypted;")
    print("   normal compiled code sits around 6.0-6.6)")


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "JET.ipa"
    main(target)
