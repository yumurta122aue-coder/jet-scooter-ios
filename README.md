# JET — scooter sharing, iOS

A ride-sharing client for e-scooters: find one on the map, scan its QR code, get
it unlocked over Bluetooth, ride, pay, get a receipt.

Built because a scooter-sharing app is really one interesting problem wearing
billing and maps as a costume — **how do you let a phone open a lock without
handing every phone a master key.** Everything here is arranged around that.

## The unlock protocol

A static key shipped in an app is a fleet-wide skeleton key: dump the IPA, pull
the key, unlock every vehicle forever. So the app never holds one. It asks the
server for a grant and the vehicle verifies that grant on its own.

```
token (36 bytes) = ride_id(8) ‖ expires_be(4) ‖ nonce(8) ‖ hmac_sha256(secret, first 20)[0..<16]
```

- **expires** — the grant dies 60 seconds after it is issued. A token sniffed off
  the air is worthless a minute later.
- **nonce** — the vehicle remembers the last nonce it accepted, so a captured
  token can't be replayed even inside its window.
- **hmac** — the vehicle verifies it offline with a fleet secret it holds. No
  round trip, no always-on connectivity needed at the lock.
- **constant-time compare** on the vehicle, because comparing signatures with
  `memcmp` leaks position information to a timing attack.

Then a **heartbeat**: the phone writes to a heartbeat characteristic every 5
seconds. The vehicle's dead-man switch drops the relay after 15 seconds of
silence. Ride away with the app killed, or carry the scooter into a van, and it
turns itself off. The security isn't in the phone being honest — it's in the
vehicle not caring whether the phone is.

### Where each piece lives

| Piece | File |
| --- | --- |
| Token issuance (stands in for the server) | [`JET/Core/Backend.swift`](JET/Core/Backend.swift) |
| BLE scan → connect → token write → heartbeat | [`JET/Core/UnlockService.swift`](JET/Core/UnlockService.swift) |
| Ride lifecycle, metering, billing | [`JET/Core/RideStore.swift`](JET/Core/RideStore.swift) |
| Vehicle firmware (ESP32-S3, HMAC verify + relay) | [`firmware/jet_vehicle/jet_vehicle.ino`](firmware/jet_vehicle/jet_vehicle.ino) |

`Backend.swift` computes the HMAC locally so the demo runs with zero
infrastructure. Swap in a real URL and the vehicle-side code does not change —
the wire format on both ends is already correct.

## The app

| Screen | What it does |
| --- | --- |
| Map | live fleet pins tinted by battery, tap for stats, unlock from the card |
| Scan | AVFoundation QR reader with debounce, plus manual code entry as fallback |
| Unlock sheet | live BLE handshake log — every line comes from the real radio |
| Ride | timer, running fare, distance, signal strength, end-ride confirmation |
| Summary | route polyline, fare breakdown, charged to balance |
| Rides | history with totals |
| Profile | balance, top-up, and a plain-language explanation of the protocol |

## Building the `.ipa` without a Mac

iOS cannot be compiled on Windows — there is no Apple toolchain for it. The
compiler runs on a **GitHub Actions macOS runner** instead, and the finished
unsigned `.ipa` comes back as a build artifact. Then **Sideloadly** on Windows
signs it with a normal Apple ID and installs it over USB.

```
push to main
   └─► macos-15 runner: brew install xcodegen → xcodegen generate
        └─► xcodebuild -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO
             └─► Payload/JET.app → zip → JET-unsigned.ipa → artifact
```

Workflow: [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml).
The Xcode project is generated from [`project.yml`](project.yml) by
[XcodeGen](https://github.com/yonaskolb/XcodeGen), so there is no `.xcodeproj`
to merge-conflict over.

### Getting it on the phone

1. **Download the artifact** — either from the Actions run page in a browser, or:
   ```
   gh run download --repo <you>/jet-scooter-ios -n JET-unsigned-ipa
   ```
2. **Install Sideloadly** — <https://sideloadly.io>. It also needs Apple's own
   iTunes (from apple.com, *not* the Microsoft Store build) for the device
   driver.
3. **Connect the iPhone by cable.** Trust the computer on the phone.
4. **Drag `JET-unsigned.ipa` into Sideloadly**, type your Apple ID, press Start.
   Sideloadly signs the app locally; your password goes to Apple, not to a
   third party. An app-specific password is safer than your real one.
5. **Trust the developer profile** — Settings → General → VPN & Device
   Management → your Apple ID → Trust.
6. **Enable Developer Mode** (iOS 16+) — Settings → Privacy & Security →
   Developer Mode → on → reboot.

A free Apple ID signature lasts **7 days**, then the app stops launching and you
re-run Sideloadly. A $99/yr developer account extends that to a year. If the
device is on iOS ≤ 17.0, **TrollStore** installs the same `.ipa` permanently
with no signature at all.

## Repo layout

```
project.yml                     XcodeGen project definition
JET/
  App/                          entry point, tab shell
  Core/                         theme, models, token authority, BLE unlocker, ride store
  Features/Map|Scan|Ride|History|Profile
  Resources/Assets.xcassets     icon (generated), accent colour
firmware/jet_vehicle/           ESP32-S3 vehicle controller
tools/make_icon.py              regenerates the app icon
tools/static_dump.py            Mach-O / IPA static analysis, no execution
tools/forge_from_dump.py        dump → recover key seed → mint a token
.github/workflows/build-ipa.yml cloud build → unsigned .ipa
```

## Static analysis

The build is unencrypted and unstripped of metadata, so a plain byte-level read
recovers a great deal. Both tools run on Windows with no device and no debugger:

```bash
python tools/static_dump.py JET.ipa        # header, dylibs, sections, symbols, strings, entropy
python tools/forge_from_dump.py JET.ipa    # recover the key seed, forge a token
```

`static_dump.py` reports the Mach-O header and flags, the full segment/section
table, linked frameworks, the symbol table, Objective-C and Swift metadata, every
interesting string bucketed by kind, and per-section entropy as a packing check.

`forge_from_dump.py` then closes the loop: a key seed left in a binary is a
published key. That is the entire argument for the token design — the app must
never hold the authority, because whatever it holds is readable. Both tools exist
so the claim is verifiable rather than asserted. See the note under
[the unlock protocol](#the-unlock-protocol).

## Running it on a Mac

```bash
brew install xcodegen
xcodegen generate
open JET.xcodeproj
```

Set your team under Signing & Capabilities if you want to run on a device
directly. Deployment target is iOS 17.0.

## Demo notes

- **The fleet is generated around your own GPS fix**, 145 m to about 780 m out
  ([`Models.swift`](JET/Core/Models.swift)), so the map opens wherever you are —
  there is no `/vehicles` backend yet. Grant location access on first launch. If
  access is refused, the app says so and falls back to a demo area rather than
  pretending you are somewhere you are not.
- The QR scanner accepts a bare id (`SK-8F31A2`), a `jet:` deep link, or a URL
  ending in the code, so it works against real scooter QR codes.
- No scooter hardware? The unlock will scan, time out after 12 seconds, and say
  so. The failure path is honest rather than faked.
