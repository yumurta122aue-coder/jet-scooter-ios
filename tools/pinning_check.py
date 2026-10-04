#!/usr/bin/env python3
"""
Does the JET client actually pin TLS?

Before writing any bypass it is worth knowing whether one is needed. This checks
three places: the manifest for a network security config, the res/xml resources
for that config, and the Dart snapshot plus dex for pinning machinery.

    python pinning_check.py [apkdir]
"""
import os
import re
import struct
import ssl
import sys
import urllib.request
import zlib

URL = "https://static.jetshr.com/goJET.apk"
UA = "Mozilla/5.0 (compatible; analysis)"

PIN_MARKERS = [
    b"badCertificateCallback", b"SecurityContext", b"setTrustedCertificates",
    b"certificatePinning", b"CertificatePinning", b"pinning", b"pinnedCertificates",
    b"sha256/", b"sha256/", b"X509Certificate", b"onBadCertificate",
    b"certificate-chain", b"publicKeyHash", b"TrustKit", b"ssl_verify_result",
]

MANIFEST_MARKERS = [
    b"networkSecurityConfig", b"usesCleartextTraffic", b"cleartextTrafficPermitted",
    b"debug-overrides", b"certificates", b"trust-anchors", b"system", b"user",
]


def ssl_ctx():
    return ssl.create_default_context()


def get_range(url, start, end, timeout=180):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(req, timeout=timeout, context=ssl_ctx()) as r:
        return r.read()


def central_directory(size):
    tail = get_range(URL, max(0, size - (1 << 20)), size - 1)
    idx = tail.rfind(b"PK\x05\x06")
    (_, _, _, _, _, cd_size, cd_offset, _) = struct.unpack("<IHHHHIIH", tail[idx:idx + 22])
    cd = get_range(URL, cd_offset, cd_offset + cd_size - 1)
    out, pos = [], 0
    while pos + 46 <= len(cd) and cd[pos:pos + 4] == b"PK\x01\x02":
        (_, _, _, _, method, _, _, _, csize, usize,
         nlen, elen, clen, _, _, _, offset) = struct.unpack("<IHHHHHHIIIHHHHHII", cd[pos:pos + 46])
        out.append({"name": cd[pos + 46:pos + 46 + nlen].decode("utf-8", "replace"),
                    "method": method, "csize": csize, "usize": usize, "offset": offset})
        pos += 46 + nlen + elen + clen
    return out


def extract(entry):
    header = get_range(URL, entry["offset"], entry["offset"] + 29)
    nlen, elen = struct.unpack("<HH", header[26:30])
    start = entry["offset"] + 30 + nlen + elen
    raw = get_range(URL, start, start + entry["csize"] - 1)
    return raw if entry["method"] == 0 else zlib.decompress(raw, -15)


def strings(data, minlen=4):
    return [m.group().decode("latin-1") for m in re.finditer(rb"[\x20-\x7e]{%d,}" % minlen, data)]


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    apkdir = sys.argv[1] if len(sys.argv) > 1 else "apk"

    req = urllib.request.Request(URL, method="HEAD", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60, context=ssl_ctx()) as r:
        size = int(r.headers["Content-Length"])
    table = central_directory(size)
    by_name = {e["name"]: e for e in table}

    print("=" * 74)
    print("  1. NETWORK SECURITY CONFIG IN THE PACKAGE")
    print("=" * 74)
    xmls = [e for e in table if e["name"].startswith("res/") and "xml" in e["name"].lower()]
    netcfg = [e for e in xmls if "network" in e["name"].lower() or "security" in e["name"].lower()]
    print(f"  res/ xml resources : {len(xmls)}")
    for e in xmls[:15]:
        print(f"      {e['name']:<48} {e['usize']:>8,}")
    print(f"  network security config present: {'YES' if netcfg else 'NO'}")

    if netcfg:
        for e in netcfg:
            data = extract(e)
            print(f"\n  --- {e['name']} ({len(data)} bytes) ---")
            for s in strings(data, 3)[:40]:
                print(f"      {s}")

    print()
    print("=" * 74)
    print("  2. MANIFEST FLAGS")
    print("=" * 74)
    if "AndroidManifest.xml" in by_name:
        mpath = os.path.join(apkdir, "AndroidManifest.xml")
        if os.path.exists(mpath):
            with open(mpath, "rb") as fh:
                manifest = fh.read()
        else:
            manifest = extract(by_name["AndroidManifest.xml"])
        found = [s for s in strings(manifest, 5) if any(m.lower() in s.lower().encode("latin-1", "ignore")
                                                        for m in MANIFEST_MARKERS)]
        for s in sorted(set(found)):
            print(f"      {s}")
        blob = manifest.decode("latin-1")
        for probe in ("networkSecurityConfig", "usesCleartextTraffic", "debuggable"):
            print(f"  contains '{probe}': {probe in blob}")

    print()
    print("=" * 74)
    print("  3. PINNING MACHINERY IN CODE")
    print("=" * 74)

    targets = []
    for root, _, files in os.walk(apkdir):
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, apkdir)
            if name.endswith(".so") or name.endswith(".dex"):
                with open(path, "rb") as fh:
                    targets.append((rel, fh.read()))

    if not targets:
        print("  no binaries collected yet — run apk_analyze.py first")
        return

    total_hits = 0
    for rel, data in sorted(targets):
        hits = []
        for marker in PIN_MARKERS:
            if marker in data:
                hits.append(marker.decode("latin-1"))
        print(f"  {rel:<34} {len(data):>12,} bytes   markers: {hits if hits else 'none'}")
        total_hits += len(hits)

    print()
    if total_hits == 0:
        print("  no pinning markers found in any collected binary.")
    else:
        print(f"  {total_hits} marker occurrences — inspect before assuming pinning.")

    print()
    print("=" * 74)
    print("  4. WHAT THIS MEANS")
    print("=" * 74)
    print("  If there is no network security config and no pinning machinery, the")
    print("  client trusts the OS trust store, and a proxy CA installed as a user")
    print("  certificate is enough to read the traffic. No bypass required.")
    print()
    print("  Android note: user CAs are not trusted by apps targeting API 24+ by")
    print("  default, so on Android the cert may need to go into the system store")
    print("  (root) or the manifest may need a debug-overrides block.")
    print("  iOS note: a user-installed CA IS trusted system-wide once enabled in")
    print("  Certificate Trust Settings, so Dart's HTTP stack will accept it.")


if __name__ == "__main__":
    main()
