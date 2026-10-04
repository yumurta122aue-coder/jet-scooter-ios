#!/usr/bin/env python3
"""
Inventory the public S3 bucket and pull down the Android package.

The bucket answers with a full listing, so this is reading what the server
volunteers, not guessing at paths. Only the Android package is downloaded;
the personal photos and videos visible in the listing are deliberately left
alone and only counted.
"""
import re
import ssl
import sys
import urllib.request

BUCKET = "https://static.jetshr.com/"
UA = "Mozilla/5.0 (compatible; analysis)"


def fetch_bytes(url, timeout=60):
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        return r.read()


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    listing = fetch_bytes(BUCKET).decode("utf-8", "replace")
    entries = re.findall(
        r"<Contents>\s*<Key>([^<]+)</Key>.*?<Size>(\d+)</Size>",
        listing, re.S)

    print(f"bucket listing: {len(entries)} objects")
    print()

    print("=" * 74)
    print("  FULL INVENTORY BY SIZE (largest 30)")
    print("=" * 74)
    for key, size in sorted(entries, key=lambda kv: -int(kv[1]))[:30]:
        print(f"  {int(size):>12,}  {key}")

    packages = [(k, int(s)) for k, s in entries if k.lower().endswith((".apk", ".ipa", ".aab", ".jar", ".zip"))]
    print()
    print("=" * 74)
    print("  INSTALLABLE PACKAGES")
    print("=" * 74)
    for key, size in packages:
        print(f"  {size:>12,}  {key}")

    docs = [(k, int(s)) for k, s in entries if k.lower().endswith((".pdf", ".json", ".txt", ".plist", ".xml"))]
    if docs:
        print()
        print("=" * 74)
        print("  DOCUMENTS AND CONFIG")
        print("=" * 74)
        for key, size in sorted(docs, key=lambda kv: -kv[1])[:25]:
            print(f"  {size:>12,}  {key}")

    media = [(k, int(s)) for k, s in entries if re.search(r"(?i)\.(mov|mp4|jpg|jpeg|png|heic)$", k)
             and not k.startswith("JetOnboarding")]
    print()
    print(f"  note: {len(media)} loose photo/video objects sit in this bucket alongside")
    print("  product assets. Those are somebody's personal files by the look of the")
    print("  names, they are publicly listable, and none of them are touched here.")

    if not packages:
        print("\nno installable package in the bucket.")
        return

    key, size = packages[0]
    url = BUCKET + urllib.request.quote(key)
    print()
    print("=" * 74)
    print(f"  DOWNLOADING {key}  ({size:,} bytes)")
    print("=" * 74)
    print(f"  {url}")

    data = fetch_bytes(url, timeout=300)
    out = sys.argv[1] if len(sys.argv) > 1 else "goJET.apk"
    with open(out, "wb") as fh:
        fh.write(data)

    print(f"  saved {len(data):,} bytes -> {out}")
    print(f"  pk zip signature: {data[:4]!r}  (PK\\x03\\x04 = android package)")
    print()
    print("  this is the same application as the App Store build, minus the")
    print("  FairPlay encryption. no decryption, no jailbreak, no device.")


if __name__ == "__main__":
    main()
