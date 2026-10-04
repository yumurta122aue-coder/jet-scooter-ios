#!/usr/bin/env python3
"""Follow the leads: the docs page, the static host, and the gojet.app domain."""
import re
import ssl
import sys
import urllib.error
import urllib.request

UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

TARGETS = [
    "https://jetshr.com/docs/index.html",
    "https://jetshr.com/docs/",
    "https://static.jetshr.com/",
    "https://gojet.app/",
    "https://api.gojet.app/",
    "https://jetshr.com/az/index.html",
]

INTERESTING = re.compile(
    r"""(https?://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]{6,200}"""
    r"""|["'`](/(?:api|v1|v2|v3|graphql|auth|oauth|mobile|fleet|ride|scooter|user|vehicle)[A-Za-z0-9._/{}$-]{0,80})["'`])""",
    re.I,
)


def fetch(url, timeout=20):
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        return r.status, r.read().decode("utf-8", "replace"), dict(r.headers)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    for url in TARGETS:
        print("=" * 74)
        print(f"  {url}")
        print("=" * 74)
        try:
            status, body, headers = fetch(url)
        except urllib.error.HTTPError as exc:
            print(f"  HTTP {exc.code} {exc.reason}")
            if exc.code in (401, 403):
                print(f"  www-authenticate: {exc.headers.get('www-authenticate')}")
                print(f"  server: {exc.headers.get('server')}")
            print()
            continue
        except Exception as exc:
            print(f"  {type(exc).__name__}: {exc}")
            print()
            continue

        print(f"  HTTP {status}, {len(body):,} bytes")
        for key in ("server", "content-type", "x-powered-by", "via", "cf-ray", "location"):
            if key in headers:
                print(f"  {key}: {headers[key]}")

        hits = INTERESTING.findall(body)
        flat = sorted({(a or b) for a, b in hits})
        flat = [h for h in flat if "google" not in h and "cloudflare" not in h and "gstatic" not in h]
        if flat:
            print(f"  --- urls and api paths ({len(flat)}) ---")
            for h in flat[:35]:
                print(f"      {h}")

        if len(body) < 4000:
            print("  --- body ---")
            for line in body.splitlines():
                line = line.strip()
                if line:
                    print(f"      {line[:150]}")
        print()


if __name__ == "__main__":
    main()
