#!/usr/bin/env python3
"""
Static analysis of the JET Android package.

A Flutter build keeps the application logic in lib/arm64-v8a/libapp.so as an AOT
Dart snapshot, so that binary matters more than the dex files. This range-fetches
it and then mines every collected artefact for the things that actually answer
the question: where does the client talk, and how does it unlock a vehicle.

    python apk_analyze.py [apkdir]
"""
import os
import re
import ssl
import struct
import sys
import urllib.request
import zlib

URL = "https://static.jetshr.com/goJET.apk"
UA = "Mozilla/5.0 (compatible; analysis)"
LIBS = ["lib/arm64-v8a/libapp.so"]

UUID_RE = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")
URL_RE = re.compile(rb"https?://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]{4,160}")
HOST_RE = re.compile(rb"\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:com|app|net|io|org|az|ru|br|kz|dev|cloud|amazonaws\.com|tech|co)\b")
PATH_RE = re.compile(rb"/(?:api|v1|v2|v3|graphql|oauth|auth|mobile|fleet|ride|rides|scooter|scooters|vehicle|vehicles|user|users|client|iot|lock|unlock)[A-Za-z0-9._/{}$-]{0,70}")

KEYWORDS = [
    b"unlock", b"lock", b"bluetooth", b"bluetoothGatt", b"peripheral", b"central",
    b"BLE", b"gatt", b"characteristic", b"writeCharacteristic", b"MTU",
    b"scooter", b"iot", b"firmware", b"ota", b"battery", b"telemetry",
    b"authorization", b"Authorization", b"Bearer", b"access_token", b"refresh_token",
    b"otp", b"sms", b"login", b"signup", b"verify",
    b"api_key", b"apiKey", b"x-api-key", b"client_secret", b"secret",
]


def ssl_ctx():
    return ssl.create_default_context()


def head(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60, context=ssl_ctx()) as r:
        return dict(r.headers)


def get_range(url, start, end, timeout=300):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(req, timeout=timeout, context=ssl_ctx()) as r:
        return r.read()


def central_directory(url, size):
    tail = get_range(url, max(0, size - (1 << 20)), size - 1)
    idx = tail.rfind(b"PK\x05\x06")
    (_, _, _, _, _, cd_size, cd_offset, _) = struct.unpack("<IHHHHIIH", tail[idx:idx + 22])
    return get_range(url, cd_offset, cd_offset + cd_size - 1)


def entries(cd):
    out, pos = [], 0
    while pos + 46 <= len(cd) and cd[pos:pos + 4] == b"PK\x01\x02":
        (_, _, _, _, method, _, _, _, csize, usize,
         nlen, elen, clen, _, _, _, offset) = struct.unpack("<IHHHHHHIIIHHHHHII", cd[pos:pos + 46])
        out.append({"name": cd[pos + 46:pos + 46 + nlen].decode("utf-8", "replace"),
                    "method": method, "csize": csize, "usize": usize, "offset": offset})
        pos += 46 + nlen + elen + clen
    return out


def extract(url, entry):
    header = get_range(url, entry["offset"], entry["offset"] + 29)
    nlen, elen = struct.unpack("<HH", header[26:30])
    start = entry["offset"] + 30 + nlen + elen
    raw = get_range(url, start, start + entry["csize"] - 1)
    return raw if entry["method"] == 0 else zlib.decompress(raw, -15)


def printable_strings(data, minlen=5):
    return [m.group().decode("latin-1") for m in re.finditer(rb"[\x20-\x7e]{%d,}" % minlen, data)]


def report(title, items, limit=40):
    items = sorted(set(items))
    print()
    print(f"  -- {title} ({len(items)}) --")
    for i in items[:limit]:
        print(f"     {i}")
    if len(items) > limit:
        print(f"     … +{len(items) - limit} more")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    apkdir = sys.argv[1] if len(sys.argv) > 1 else "apk"
    os.makedirs(apkdir, exist_ok=True)

    print("=" * 74)
    print("  JET ANDROID PACKAGE — STATIC ANALYSIS")
    print("=" * 74)

    headers = head(URL)
    size = int(headers["Content-Length"])
    table = entries(central_directory(URL, size))
    by_name = {e["name"]: e for e in table}

    for lib in LIBS:
        entry = by_name.get(lib)
        if not entry:
            print(f"  {lib}: not present")
            continue
        target = os.path.join(apkdir, lib.replace("/", os.sep))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if os.path.exists(target) and os.path.getsize(target) == entry["usize"]:
            print(f"  {lib}: already cached ({entry['usize']:,} bytes)")
            continue
        print(f"  fetching {lib} ({entry['usize']:,} bytes uncompressed)…")
        data = extract(URL, entry)
        with open(target, "wb") as fh:
            fh.write(data)
        print(f"  saved {len(data):,} bytes")

    blobs = {}
    for root, _, files in os.walk(apkdir):
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, apkdir)
            with open(path, "rb") as fh:
                blobs[rel] = fh.read()

    print()
    print(f"  analysing {len(blobs)} artefacts: {', '.join(sorted(blobs))}")

    combined = b"\n".join(blobs.values())

    print()
    print("=" * 74)
    print("  WHERE THE CLIENT TALKS")
    print("=" * 74)
    urls = [u.decode("latin-1") for u in URL_RE.findall(combined)]
    report("full urls", urls)

    hosts = [h.decode("latin-1") for h in HOST_RE.findall(combined)
             if not h.decode("latin-1").endswith((".png", ".ttf", ".jpg", ".json"))]
    report("hostnames", hosts)

    paths = [p.decode("latin-1") for p in PATH_RE.findall(combined)
             if len(p) > 6 and not p.endswith((b".dart", b".so", b".png"))]
    report("api-shaped paths", paths, limit=60)

    print()
    print("=" * 74)
    print("  BLUETOOTH AND UNLOCK")
    print("=" * 74)
    uuids = sorted(set(UUID_RE.findall(combined.decode("latin-1"))))
    report("UUIDs", uuids, limit=50)

    for kw in [b"unlock", b"bluetooth", b"gatt", b"characteristic", b"peripheral"]:
        hits = [s for s in printable_strings(combined, 6) if kw.lower() in s.lower().encode("latin-1", "ignore")]
        if hits:
            report(f"strings containing '{kw.decode()}'", hits, limit=25)

    print()
    print("=" * 74)
    print("  CREDENTIAL SHAPED")
    print("=" * 74)
    for kw in KEYWORDS:
        if kw.lower() in (b"unlock", b"lock", b"bluetooth", b"gatt", b"characteristic", b"peripheral"):
            continue
        hits = [s for s in printable_strings(combined, 5) if kw in s.encode("latin-1", "ignore")]
        if hits and len(hits) < 400:
            report(f"'{kw.decode()}'", hits, limit=12)


if __name__ == "__main__":
    main()
