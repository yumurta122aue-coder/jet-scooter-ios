#!/usr/bin/env python3
"""
Deep string mining of the Dart AOT snapshot.

The earlier pass filtered too aggressively and found nothing. Route fragments in
a Dart snapshot are often stored as separate segments that get joined at runtime,
so this prints everything that could be a path segment, endpoint, header name or
protocol constant, in both Latin-1 and UTF-16.

    python dart_deep.py [apkdir]
"""
import os
import re
import sys

APK = "apk"
SNAPSHOT = os.path.join("lib", "arm64-v8a", "libapp.so")

# Everything we would want to see if it is present at all.
TOPICS = {
    "auth":     ["auth", "login", "logout", "token", "refresh", "jwt", "bearer",
                 "session", "otp", "sms", "code", "verify", "signup", "register",
                 "phone", "password", "pin"],
    "ride":     ["ride", "rides", "order", "orders", "start", "stop", "finish",
                 "end", "begin", "active", "history", "trip", "unlock", "lock",
                 "reserve", "booking", "pause"],
    "vehicle":  ["vehicle", "vehicles", "scooter", "scooters", "iot", "device",
                 "battery", "firmware", "telemetry", "qr", "qrcode", "code",
                 "scan", "nearby", "map", "zone", "parking"],
    "money":    ["balance", "wallet", "topup", "payment", "payments", "card",
                 "cards", "price", "tariff", "promo", "referral", "invoice",
                 "receipt", "refund", "bepaid"],
    "generic":  ["config", "settings", "version", "profile", "users", "me",
                 "notifications", "support", "faq", "documents", "terms",
                 "v1", "v2", "api", "graphql", "rest"],
}

HEADER_RE = re.compile(
    rb"(?i)\b(x-[a-z][a-z0-9-]{2,32}|authorization|content-type|accept-language|"
    rb"user-agent|x-api-version|x-device-id|x-app-version|x-platform|x-request-id)\b")

PATH_RE = re.compile(r"/[A-Za-z0-9_][A-Za-z0-9._/-]{1,60}")


def ascii_runs(data, minlen=4):
    for m in re.finditer(rb"[\x20-\x7e]{%d,}" % minlen, data):
        yield m.group().decode("latin-1")


def utf16_runs(data, minlen=4):
    # UTF-16LE strings land as printable, NUL, printable, NUL …
    for m in re.finditer(rb"(?:[\x20-\x7e]\x00){%d,}" % minlen, data):
        yield m.group().decode("utf-16-le", "replace")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    apkdir = sys.argv[1] if len(sys.argv) > 1 else APK
    target = os.path.join(apkdir, SNAPSHOT)
    if not os.path.exists(target):
        print(f"missing {target}")
        return

    with open(target, "rb") as fh:
        data = fh.read()
    print(f"libapp.so: {len(data):,} bytes")

    pool = set(ascii_runs(data, 3)) | set(utf16_runs(data, 3))
    print(f"distinct strings extracted: {len(pool):,}")

    # --- 1. host and url shaped -------------------------------------------
    print()
    print("=" * 74)
    print("  HOSTS AND URLS")
    print("=" * 74)
    urls = sorted({s for s in pool if s.startswith(("http://", "https://"))})
    for s in urls:
        print(f"  {s}")

    hosts = sorted({s for s in pool
                    if re.fullmatch(r"[a-z0-9.-]+\.(app|com|net|io|org|az|ru|br|kz|dev|ee|by)", s, re.I)})
    print(f"\n  bare hostnames: {len(hosts)}")
    for s in hosts:
        print(f"  {s}")

    # --- 2. path segments -------------------------------------------------
    print()
    print("=" * 74)
    print("  PATH-SHAPED STRINGS")
    print("=" * 74)
    paths = sorted({s for s in pool if PATH_RE.fullmatch(s) and " " not in s})
    print(f"  total: {len(paths)}")
    for s in paths[:80]:
        print(f"  {s}")

    # --- 3. topics --------------------------------------------------------
    for topic, words in TOPICS.items():
        hits = set()
        for s in pool:
            low = s.lower()
            if len(s) > 90 or " " in s and len(s) > 50:
                continue
            for w in words:
                if w in low:
                    hits.add(s)
                    break
        if not hits:
            continue
        print()
        print("=" * 74)
        print(f"  TOPIC: {topic}  ({len(hits)} strings)")
        print("=" * 74)
        for s in sorted(hits)[:70]:
            print(f"  {s}")

    # --- 4. headers -------------------------------------------------------
    print()
    print("=" * 74)
    print("  HEADER NAMES")
    print("=" * 74)
    headers = set()
    for m in HEADER_RE.finditer(data):
        headers.add(m.group().decode("latin-1"))
    for s in sorted(headers):
        print(f"  {s}")


if __name__ == "__main__":
    main()
