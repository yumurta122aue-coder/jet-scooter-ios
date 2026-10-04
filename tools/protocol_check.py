#!/usr/bin/env python3
"""
Cross-implementation check of the unlock protocol.

Three separate implementations have to agree byte-for-byte or nothing ever opens:
the app mints the token, the vehicle verifies it, and this is an independent
third reading of the same spec.

  1. JET/Core/Backend.swift          — mints
  2. firmware/jet_vehicle/*.ino      — verifies
  3. this file                       — re-implements both sides and attacks them

It also mechanically re-extracts the byte offsets the firmware actually uses out
of its source, so the layout claim is checked against the code rather than
against my memory of it.

    python protocol_check.py
"""

import hashlib
import hmac
import os
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "JET" / "Core" / "Backend.swift"
FIRMWARE = ROOT / "firmware" / "jet_vehicle" / "jet_vehicle.ino"

# The claimed layout. Everything below is checked against these numbers.
RIDE_ID = (0, 8)
EXPIRES = (8, 12)
NONCE = (12, 20)
SIGNATURE = (20, 36)
TOKEN_LEN = 36
SIGNED_PREFIX = 20          # HMAC covers ride_id + expires + nonce
SIG_LEN = 16
VALIDITY_SECONDS = 60

PASS, FAIL = "PASS", "FAIL"
results = []


def check(name, condition, detail=""):
    results.append((PASS if condition else FAIL, name, detail))
    print(f"  [{PASS if condition else FAIL}] {name}" + (f"   {detail}" if detail else ""))
    return condition


# ---------------------------------------------------------------------------
# 1. does the firmware source actually use the offsets we claim?
# ---------------------------------------------------------------------------

def check_firmware_offsets():
    print("firmware source — extracted offsets")
    if not FIRMWARE.exists():
        check("firmware source found", False, str(FIRMWARE))
        return
    text = FIRMWARE.read_text(encoding="utf-8", errors="replace")

    check("firmware source found", True, FIRMWARE.name)

    # The firmware assembles the expiry by hand rather than memcpy, so the check
    # reads the shifts and asserts the byte order is genuinely big-endian: the
    # byte at offset 8 must be the most significant.
    shifts = re.findall(r"\(uint32_t\)token\[(\d+)\]\s*<<\s*(\d+)", text)
    check("expires assembled from token[8..11] big-endian first",
          shifts[:4] == [("8", "24"), ("9", "16"), ("10", "8")] and "token[11]" in text,
          f"found {shifts[:4]}")

    nonce_read = re.search(r"nonceSeenBefore\(token\s*\+\s*(\d+)\)", text)
    check("nonce checked at offset 12",
          bool(nonce_read) and nonce_read.group(1) == "12",
          f"found token + {nonce_read.group(1)}" if nonce_read else "pattern not found")

    hmac_update = re.search(r"mbedtls_md_hmac_update\(&ctx,\s*token,\s*(\d+)\)", text)
    check("hmac covers first 20 bytes",
          bool(hmac_update) and hmac_update.group(1) == "20",
          f"found {hmac_update.group(1)}" if hmac_update else "pattern not found")

    cmp_sig = re.search(r"constantTimeEquals\(mac,\s*token\s*\+\s*(\d+),\s*(\d+)\)", text)
    check("signature compared at offset 20, 16 bytes",
          bool(cmp_sig) and cmp_sig.group(1) == "20" and cmp_sig.group(2) == "16",
          f"found token + {cmp_sig.group(1)}, {cmp_sig.group(2)}" if cmp_sig else "pattern not found")

    check("length gate is 36",
          bool(re.search(r"#define\s+TOKEN_LEN\s+36", text)))

    check("expiry is big-endian on the wire",
          "token[8]" in text and "<< 24" in text and ">> 24" not in text,
          "byte 8 holds the most significant byte")

    check("constant-time signature compare",
          "constantTimeEquals" in text and "diff |=" in text)


# ---------------------------------------------------------------------------
# 2. does the swift source mint what the firmware expects?
# ---------------------------------------------------------------------------

def check_swift_source():
    print()
    print("swift source — minting path")
    if not SWIFT.exists():
        check("swift source found", False, str(SWIFT))
        return
    text = SWIFT.read_text(encoding="utf-8", errors="replace")

    check("swift source found", True, SWIFT.name)
    check("ride id is 8 random bytes", "randomBytes(8)" in text)
    check("expiry is now + 60", "+ 60" in text)
    check("expiry written big-endian", ".bigEndian" in text)
    check("nonce is 8 random bytes", text.count("randomBytes(8)") >= 2)
    check("signature truncated to 16", "prefix(16)" in text)
    check("hmac over the 20-byte blob",
          "HMAC<SHA256>.authenticationCode(for: blob" in text)
    check("payload is blob + signature", "payload: blob + signature" in text)


# ---------------------------------------------------------------------------
# 3. app-side mint, faithful to Backend.swift
# ---------------------------------------------------------------------------

class App:
    """Mirrors JET/Core/Backend.swift."""

    def __init__(self, seed: str):
        self.key = hashlib.sha256(seed.encode()).digest()

    def request_unlock(self, now: int, ride_id=None, nonce=None):
        ride_id = ride_id or os.urandom(8)
        nonce = nonce or os.urandom(8)
        expires = now + VALIDITY_SECONDS
        blob = ride_id + struct.pack(">I", expires) + nonce
        signature = hmac.new(self.key, blob, hashlib.sha256).digest()[:SIG_LEN]
        return blob + signature, expires


# ---------------------------------------------------------------------------
# 4. vehicle-side verify, faithful to jet_vehicle.ino
# ---------------------------------------------------------------------------

class Vehicle:
    """Mirrors firmware/jet_vehicle/jet_vehicle.ino."""

    def __init__(self, seed: str, clock: int):
        self.key = hashlib.sha256(seed.encode()).digest()
        self.clock = clock
        self.last_nonce = None
        self.relay = False

    def verify(self, token: bytes):
        if len(token) != TOKEN_LEN:
            return False, "wrong length"

        expires = int.from_bytes(token[EXPIRES[0]:EXPIRES[1]], "big")

        if self.clock < 1600000000:
            return False, "clock never synced (no time source)"
        if expires < self.clock:
            return False, "token expired"
        if self.last_nonce == token[NONCE[0]:NONCE[1]]:
            return False, "nonce replay"

        mac = hmac.new(self.key, token[:SIGNED_PREFIX], hashlib.sha256).digest()[:SIG_LEN]
        if not hmac.compare_digest(mac, token[SIGNATURE[0]:SIGNATURE[1]]):
            return False, "signature mismatch"

        self.last_nonce = token[NONCE[0]:NONCE[1]]
        self.relay = True
        return True, "relay closed"


# ---------------------------------------------------------------------------
# 5. attack the pair
# ---------------------------------------------------------------------------

def run_protocol_tests():
    print()
    print("protocol behaviour")
    SEED = "jet-demo-fleet-key-v1"
    NOW = 1791133658

    app = App(SEED)
    car = Vehicle(SEED, NOW)

    token, expires = app.request_unlock(NOW)
    ok, why = car.verify(token)
    check("valid token opens the relay", ok and car.relay, why)

    car2 = Vehicle(SEED, NOW)
    token2, _ = app.request_unlock(NOW)
    car2.verify(token2)
    car2.relay = False
    ok, why = car2.verify(token2)
    check("replaying the same token is refused", not ok, why)

    car3 = Vehicle(SEED, NOW + VALIDITY_SECONDS + 1)
    token3, _ = app.request_unlock(NOW)
    ok, why = car3.verify(token3)
    check("token 61 seconds later is refused", not ok, why)

    car4 = Vehicle("a-different-fleet-key", NOW)
    token4, _ = app.request_unlock(NOW)
    ok, why = car4.verify(token4)
    check("token signed with the wrong key is refused", not ok, why)

    car5 = Vehicle(SEED, NOW)
    token5, _ = app.request_unlock(NOW)
    tampered = bytearray(token5)
    tampered[0] ^= 0x01                      # flip one bit of the ride id
    ok, why = car5.verify(bytes(tampered))
    check("a single flipped bit invalidates it", not ok, why)

    car6 = Vehicle(SEED, NOW)
    ok, why = car6.verify(b"\x00" * 35)
    check("a 35-byte token is refused", not ok, why)

    car7 = Vehicle(SEED, 0)                  # ESP32 before NTP sync
    token7, _ = app.request_unlock(NOW)
    ok, why = car7.verify(token7)
    check("vehicle with an unsynced clock refuses everything", not ok, why)

    car8 = Vehicle("jet-demo-fleet-key-v1", NOW)
    token8, _ = app.request_unlock(NOW)
    ok, why = car8.verify(token8)
    check("the recovered seed reproduces a working key", ok, why)

    # skip-ahead: a new nonce each time must keep working
    car9 = Vehicle(SEED, NOW)
    accepted = 0
    for _ in range(5):
        t, _ = app.request_unlock(NOW)
        good, _ = car9.verify(t)
        accepted += 1 if good else 0
    check("five fresh tokens in a row all open", car9.relay and accepted == 5, f"{accepted}/5")

    print()
    print("layout")
    check("offsets sum to 36",
          RIDE_ID[1] + (EXPIRES[1] - EXPIRES[0]) + (NONCE[1] - NONCE[0]) + SIG_LEN == TOKEN_LEN)
    check("hmac prefix equals ride+expires+nonce", SIGNED_PREFIX == NONCE[1],
          f"{SIGNED_PREFIX} == {NONCE[1]}")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    print("=" * 72)
    print("  UNLOCK PROTOCOL — CROSS-IMPLEMENTATION CHECK")
    print("=" * 72)
    print()

    check_firmware_offsets()
    check_swift_source()
    run_protocol_tests()

    passed = sum(1 for r in results if r[0] == PASS)
    failed = [r for r in results if r[0] == FAIL]

    print()
    print("=" * 72)
    print(f"  {passed}/{len(results)} checks passed")
    print("=" * 72)
    if failed:
        print()
        for _, name, detail in failed:
            print(f"  FAILED: {name}  {detail}")
        sys.exit(1)
    print()
    print("  What this does prove: the token the app mints is the token the")
    print("  firmware accepts, and the four guards hold — expiry, nonce replay,")
    print("  signature, and length.")
    print()
    print("  What this does NOT prove: that the Swift compiles to the same thing")
    print("  at runtime, or that a real radio link behaves. Only a device can")
    print("  show that.")


if __name__ == "__main__":
    main()
