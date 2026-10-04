#!/usr/bin/env python3
"""
Remote ZIP reader for the JET Android package.

Downloads nothing it does not need. Reads the end-of-central-directory record,
walks the central directory, and then range-fetches only the entries that matter
(the manifest and the dex files), instead of pulling 100 MB.

    python apk_remote.py [outdir]
"""

import os
import re
import struct
import ssl
import sys
import urllib.error
import urllib.request
import zlib

URL = "https://static.jetshr.com/goJET.apk"
UA = "Mozilla/5.0 (compatible; analysis)"

EOCD_SIG = b"PK\x05\x06"
CD_SIG = b"PK\x01\x02"
LFH_SIG = b"PK\x03\x04"
ZIP64_EOCD_SIG = b"PK\x06\x06"
ZIP64_LOC_SIG = b"PK\x06\x07"


def ssl_ctx():
    return ssl.create_default_context()


def head(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60, context=ssl_ctx()) as r:
        return r.status, dict(r.headers)


def get_range(url, start, end, timeout=180):
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Range": f"bytes={start}-{end}",
    })
    with urllib.request.urlopen(req, timeout=timeout, context=ssl_ctx()) as r:
        return r.status, r.read()


def read_tail(url, size, window=1 << 20):
    """Grab the last megabyte, which holds the central directory."""
    start = max(0, size - window)
    status, data = get_range(url, start, size - 1)
    return data, start


def parse_central_directory(tail, tail_offset, url, size):
    idx = tail.rfind(EOCD_SIG)
    if idx < 0:
        raise ValueError("no end-of-central-directory record in the tail window")

    (_, _, _, _, total, cd_size, cd_offset, _) = struct.unpack("<IHHHHIIH", tail[idx:idx + 22])

    # ZIP64: the classic record saturates its fields.
    if total == 0xFFFF or cd_size == 0xFFFFFFFF or cd_offset == 0xFFFFFFFF:
        loc = tail.rfind(ZIP64_LOC_SIG)
        if loc >= 0:
            zip64_eocd_offset = struct.unpack("<Q", tail[loc + 8:loc + 16])[0]
            _, zip64 = get_range(url, zip64_eocd_offset, zip64_eocd_offset + 55)
            total = struct.unpack("<Q", zip64[32:40])[0]
            cd_size = struct.unpack("<Q", zip64[40:48])[0]
            cd_offset = struct.unpack("<Q", zip64[48:56])[0]

    # The central directory may sit before the tail window, so fetch it outright.
    _, cd = get_range(url, cd_offset, cd_offset + cd_size - 1)

    entries = []
    pos = 0
    while pos + 46 <= len(cd) and cd[pos:pos + 4] == CD_SIG:
        (_, _, _, flags, method, _, _, crc, csize, usize,
         nlen, elen, clen, _, _, _, local_offset) = struct.unpack("<IHHHHHHIIIHHHHHII", cd[pos:pos + 46])
        name = cd[pos + 46:pos + 46 + nlen].decode("utf-8", "replace")
        entries.append({
            "name": name, "method": method, "csize": csize, "usize": usize,
            "offset": local_offset, "crc": crc,
        })
        pos += 46 + nlen + elen + clen

    return total, entries


def extract(url, entry, timeout=180):
    """Read one entry: local header, then just its compressed payload."""
    _, header = get_range(url, entry["offset"], entry["offset"] + 29, timeout)
    if header[:4] != LFH_SIG:
        raise ValueError(f"{entry['name']}: bad local file header")
    nlen, elen = struct.unpack("<HH", header[26:30])
    data_start = entry["offset"] + 30 + nlen + elen
    _, raw = get_range(url, data_start, data_start + entry["csize"] - 1, timeout)
    if entry["method"] == 0:
        return raw
    if entry["method"] == 8:
        return zlib.decompress(raw, -15)
    raise ValueError(f"{entry['name']}: unsupported method {entry['method']}")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    outdir = sys.argv[1] if len(sys.argv) > 1 else "apk"
    os.makedirs(outdir, exist_ok=True)

    print("=" * 74)
    print("  REMOTE APK READER")
    print("=" * 74)

    status, headers = head(URL)
    size = int(headers.get("Content-Length", 0))
    print(f"  url              : {URL}")
    print(f"  HTTP             : {status}")
    print(f"  size             : {size:,} bytes")
    print(f"  accept-ranges    : {headers.get('Accept-Ranges')}")
    print(f"  last-modified    : {headers.get('Last-Modified')}")
    print(f"  etag             : {headers.get('ETag')}")

    print()
    print("  reading central directory…")
    tail, tail_offset = read_tail(URL, size)
    total, entries = parse_central_directory(tail, tail_offset, URL, size)
    print(f"  entries declared : {total}")
    print(f"  entries parsed   : {len(entries)}")

    dex = [e for e in entries if re.match(r"classes\d*\.dex$", e["name"])]
    assets = [e for e in entries if e["name"].startswith("assets/")]
    manifest = [e for e in entries if e["name"] == "AndroidManifest.xml"]
    libs = [e for e in entries if e["name"].startswith("lib/")]

    print()
    print(f"  classes*.dex     : {len(dex)}  ({sum(e['usize'] for e in dex):,} bytes uncompressed)")
    for e in sorted(dex, key=lambda e: -e["usize"]):
        print(f"      {e['name']:<22} {e['usize']:>12,}")

    print(f"  AndroidManifest  : {len(manifest)}")
    print(f"  native libs      : {len(libs)}")
    for e in libs[:12]:
        print(f"      {e['name']:<44} {e['usize']:>12,}")

    print(f"  assets           : {len(assets)}")
    for e in sorted(assets, key=lambda e: -e["usize"])[:25]:
        print(f"      {e['name']:<52} {e['usize']:>10,}")

    wanted = manifest + dex
    # small text-ish assets often hold config
    wanted += [e for e in assets if e["usize"] < 400_000
               and e["name"].lower().endswith((".json", ".xml", ".txt", ".plist", ".properties"))]

    print()
    print(f"  fetching {len(wanted)} entries ({sum(e['csize'] for e in wanted):,} compressed bytes)")

    for entry in wanted:
        target = os.path.join(outdir, entry["name"].replace("/", os.sep))
        os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
        try:
            data = extract(URL, entry)
        except Exception as exc:
            print(f"      FAILED {entry['name']}: {type(exc).__name__}: {exc}")
            continue
        with open(target, "wb") as fh:
            fh.write(data)
        mark = "ok " if len(data) == entry["usize"] else "!! "
        print(f"      [{mark}] {entry['name']:<30} {len(data):>12,} bytes")

    print()
    print(f"  written to {os.path.abspath(outdir)}")


if __name__ == "__main__":
    main()
