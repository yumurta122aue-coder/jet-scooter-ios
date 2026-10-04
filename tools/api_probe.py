#!/usr/bin/env python3
"""
Two leads: the API host, and an S3 bucket that answered with a listing.

For the API host this asks only for documentation-shaped paths that a service
publishes on purpose (docs, swagger, openapi, health). No authentication is
attempted, no parameters are fuzzed, nothing is enumerated beyond that.
"""
import re
import ssl
import sys
import urllib.error
import urllib.request

UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

API_HOSTS = [
    "https://api.gojet.app/",
    "https://api.gojet.app/docs",
    "https://api.gojet.app/swagger",
    "https://api.gojet.app/swagger/index.html",
    "https://api.gojet.app/openapi.json",
    "https://api.gojet.app/v1",
    "https://api.gojet.app/v2",
    "https://api.gojet.app/health",
    "https://api.gojet.app/api/v1",
]


def fetch(url, timeout=20):
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "application/json, text/html, */*",
    })
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        return r.status, r.read().decode("utf-8", "replace"), dict(r.headers)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    print("=" * 74)
    print("  API HOST: api.gojet.app")
    print("=" * 74)
    for url in API_HOSTS:
        try:
            status, body, headers = fetch(url)
        except urllib.error.HTTPError as exc:
            extra = ""
            if exc.headers.get("www-authenticate"):
                extra = f"  www-authenticate: {exc.headers['www-authenticate']}"
            if exc.headers.get("allow"):
                extra += f"  allow: {exc.headers['allow']}"
            print(f"  {url:<50} HTTP {exc.code}{extra}")
            continue
        except Exception as exc:
            print(f"  {url:<50} {type(exc).__name__}: {exc}")
            continue

        ctype = headers.get("content-type", "?")
        print(f"  {url:<50} HTTP {status}  {ctype}  {len(body)}B")
        snippet = body.strip()[:400].replace("\n", " ")
        if snippet:
            print(f"      {snippet}")

    print()
    print("=" * 74)
    print("  S3 BUCKET: static.jetshr.com")
    print("=" * 74)
    try:
        status, body, headers = fetch("https://static.jetshr.com/")
        print(f"  HTTP {status}  {len(body):,} bytes  server={headers.get('server')}")
        keys = re.findall(r"<Key>([^<]+)</Key>", body)
        prefixes = re.findall(r"<Prefix>([^<]*)</Prefix>", body)
        print(f"  keys: {len(keys)}   common prefixes: {len(prefixes)}")

        if prefixes:
            print("  top-level folders:")
            for p in sorted(set(prefixes))[:30]:
                print(f"      {p}")

        if keys:
            print("  sample keys:")
            for k in sorted(keys)[:40]:
                print(f"      {k}")

            interesting = [k for k in keys if re.search(
                r"(?i)(api|config|env|json|\.ipa|\.apk|plist|mobile|app|version|swagger|openapi)", k)]
            if interesting:
                print("  keys worth a look:")
                for k in sorted(interesting)[:40]:
                    print(f"      {k}")
    except Exception as exc:
        print(f"  {type(exc).__name__}: {exc}")


if __name__ == "__main__":
    main()
