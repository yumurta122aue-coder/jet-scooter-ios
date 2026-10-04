#!/usr/bin/env python3
"""Verify a built .ipa: integrity, bundle metadata, architecture, entitlements, features."""
import plistlib
import struct
import sys
import zipfile


def main(path):
    z = zipfile.ZipFile(path)
    names = z.namelist()
    app = sorted({n.split("/")[1] for n in names if n.startswith("Payload/") and len(n.split("/")) > 2})[0]
    info = plistlib.loads(z.read(f"Payload/{app}/Info.plist"))
    binary_path = f"Payload/{app}/{info['CFBundleExecutable']}"
    binary = z.read(binary_path)

    print(f"file        : {path}")
    print(f"size        : {sum(i.file_size for i in z.infolist()):,} bytes uncompressed")
    print(f"integrity   : {'OK' if z.testzip() is None else 'CORRUPT'}")
    print(f"bundle id   : {info['CFBundleIdentifier']}")
    print(f"version     : {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")
    print(f"min ios     : {info['MinimumOSVersion']}")
    print(f"executable  : {binary_path}  ({len(binary):,} bytes)")

    cputype = struct.unpack_from("<I", binary, 4)[0]
    arch = {0x0100000C: "arm64", 0x0000000C: "arm", 0x01000007: "x86_64"}.get(cputype, hex(cputype))
    print(f"arch        : {arch}")
    print(f"code sign   : {'signed' if any('_CodeSignature' in n for n in names) else 'unsigned'}")
    print(f"provision   : {'present' if any('embedded.mobileprovision' in n for n in names) else 'absent'}")

    print()
    print("privacy strings:")
    for key in sorted(info):
        if key.startswith("NS") and "Usage" in key:
            print(f"  {key}")

    print()
    print("feature probes (present in the compiled binary):")
    probes = [
        ("unlock service", b"UnlockService"),
        ("GATT unlock uuid", b"6A4E0001"),
        ("HMAC token signing", b"requestUnlock"),
        ("fleet key seed", b"jet-demo-fleet-key-v1"),
        ("unfiltered BLE scan", b"scanForPeripherals"),
        ("BLE recon module", b"BLEScanner"),
        ("GATT enumeration", b"discoverCharacteristics"),
        ("NFC tag session", b"NFCTagReaderSession"),
        ("raw MIFARE command", b"sendMiFareCommand"),
        ("GET_VERSION decode", b"interpretGetVersion"),
        ("NFC entitlement key", b"com.apple.developer.nfc.readersession"),
    ]
    for label, needle in probes:
        mark = "yes" if needle in binary else "no "
        print(f"  [{mark}] {label}")

    print()
    print("binary strings worth noting:")
    for needle in (b"/Users/runner/work", b"SK-8F31A2", b"SK-"):
        print(f"  {needle.decode():<20} {'present' if needle in binary else 'absent'}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "JET.ipa")
