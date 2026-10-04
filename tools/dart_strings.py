#!/usr/bin/env python3
"""
Targeted extraction from the Dart AOT snapshot.

Flutter compiles Dart ahead of time, so route strings sit in libapp.so as
literals in a snapshot rather than in anything readable like a route table.
This pulls the ones that look like API routes or auth vocabulary.

    python dart_strings.py [apkdir]
"""
import os
import re
import sys

PATTERNS = [
    ("routes", re.compile(rb"(?:^|[\x00-\x1f])((?:api/)?v\d/[A-Za-z0-9._/{}$-]{2,70})")),
    ("auth vocabulary", re.compile(rb"[\x20-\x7e]{4,60}")),
]

ROUTE_HINT = re.compile(
    rb"(?i)(auth|token|login|logout|otp|sms|phone|verify|signup|sign-?up|register|"
    rb"ride|rides|order|orders|start|stop|finish|end|payment|payments|card|cards|"
    rb"balance|wallet|topup|top-?up|vehicle|vehicles|scooter|scooters|scan|qr|"
    rb"unlock|lock|reserve|parking|zone|zones|tariff|price|promo|referral|profile|"
    rb"user|users|me|refresh|session|device|fcm|push|config|settings|version)")

ALLOWED_TAIL = re.compile(rb"^[A-Za-z0-9._/{}$-]+$")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    apkdir = sys.argv[1] if len(sys.argv) > 1 else "apk"
    target = os.path.join(apkdir, "lib", "arm64-v8a", "libapp.so")
    if not os.path.exists(target):
        print(f"missing {target} — run apk_analyze.py first")
        return

    with open(target, "rb") as fh:
        data = fh.read()
    print(f"libapp.so: {len(data):,} bytes")

    # Route-shaped strings: short, slash-separated, no spaces.
    candidates = set()
    for m in re.finditer(rb"[\x20-\x7e]{3,80}", data):
        s = m.group()
        if b" " in s or b"/" not in s:
            continue
        if not ALLOWED_TAIL.match(s):
            continue
        if ROUTE_HINT.search(s):
            candidates.add(s.decode("latin-1"))

    print()
    print("=" * 74)
    print(f"  ROUTE-SHAPED STRINGS ({len(candidates)})")
    print("=" * 74)
    for s in sorted(candidates):
        print(f"  {s}")

    # Endpoint-ish: contains a version segment.
    versioned = sorted({s for s in candidates if re.search(r"v\d/", s)})
    print()
    print("=" * 74)
    print(f"  VERSIONED ENDPOINTS ({len(versioned)})")
    print("=" * 74)
    for s in versioned:
        print(f"  {s}")

    # Auth vocabulary, plain words.
    print()
    print("=" * 74)
    print("  AUTH AND ORDER VOCABULARY")
    print("=" * 74)
    words = set()
    for m in re.finditer(rb"[\x20-\x7e]{3,48}", data):
        s = m.group()
        if b" " in s or b"." in s:
            continue
        if re.fullmatch(rb"(?i)(otp|sms|jwt|bearer|refresh|access|token|auth|login|logout|"
                        rb"phone|phoneNumber|verificationCode|smsCode|password|session|"
                        rb"orderStatus|orderId|rideId|vehicleId|scooterId|qrCode|"
                        rb"unlockFee|unlockPrice|pricePerMinute|startRide|stopRide|"
                        rb"endRide|finishRide|createOrder|cancelOrder|pendingTransport|"
                        rb"transportUnlock|failedTransport)", s):
            words.add(s.decode("latin-1"))
    for w in sorted(words):
        print(f"  {w}")

    print()
    print("=" * 74)
    print("  API HOSTS AND HEADERS")
    print("=" * 74)
    for pattern in (rb"api\.gojet\.app[A-Za-z0-9._/{}$-]*",
                    rb"(?i)(x-[a-z-]{2,30})",
                    rb"(?i)(authorization|bearer|content-type|accept-language|x-device|x-app)"):
        hits = sorted({m.group().decode("latin-1") for m in re.finditer(pattern, data)})
        if hits:
            print(f"  -- {pattern.decode('latin-1','ignore')[:40]} ({len(hits)})")
            for h in hits[:25]:
                print(f"       {h}")


if __name__ == "__main__":
    main()
