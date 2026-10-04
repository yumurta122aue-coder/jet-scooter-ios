#!/usr/bin/env python3
"""
Public web recon for A JET-style scooter operator's API surface.

Reads only what is publicly served: the marketing site's HTML, its JavaScript
bundles, and any endpoints named inside them. No authentication is attempted and
no request is made to an endpoint that requires one.

    python web_recon.py
"""

import json
import re
import ssl
import sys
import urllib.error
import urllib.request

UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

HOSTS = [
    "https://jetshr.com/mn/index.html",
    "https://dev.jetshr.com/",
    "https://start.jetshr.com/",
    "https://power.jetshr.com/",
    "https://ge.jetshr.com/",
]

URL_RE = re.compile(r"""["'`(](https?://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]{4,200})["'`)]""")
SRC_RE = re.compile(r"""<script[^>]+src=["']([^"']+)["']""", re.I)
HREF_RE = re.compile(r"""<link[^>]+href=["']([^"']+)["']""", re.I)
APIPATH_RE = re.compile(r"""["'`](/(?:api|v1|v2|v3|graphql|auth|oauth|mobile|fleet|ride|scooter)[A-Za-z0-9._/{}$-]{0,80})["'`]""", re.I)


def fetch(url, timeout=20):
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/javascript,*/*",
        "Accept-Language": "en",
    })
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as response:
        return response.status, response.read().decode("utf-8", "replace")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    print("=" * 74)
    print("  PUBLIC WEB RECON")
    print("=" * 74)

    try:
        status, _ = fetch("https://example.com", timeout=15)
        print(f"\nnetwork reachable: yes (example.com -> {status})")
    except Exception as exc:
        print(f"\nnetwork reachable: NO -> {type(exc).__name__}: {exc}")
        print("python's TLS stack is blocked too; stopping.")
        return

    bundles = []
    for host in HOSTS:
        print()
        print(f"--- {host}")
        try:
            status, html = fetch(host)
        except Exception as exc:
            print(f"    failed: {type(exc).__name__}: {exc}")
            continue

        print(f"    HTTP {status}, {len(html)} bytes")

        scripts = SRC_RE.findall(html)
        links = HREF_RE.findall(html)
        print(f"    <script src> : {len(scripts)}")
        for s in scripts[:12]:
            print(f"        {s}")
            bundles.append((host, s))
        print(f"    <link href>  : {len(links)}")
        for l in links[:6]:
            print(f"        {l}")

        absolute = sorted(set(URL_RE.findall(html)))
        if absolute:
            print(f"    absolute urls in html: {len(absolute)}")
            for u in absolute[:20]:
                print(f"        {u}")

        paths = sorted(set(APIPATH_RE.findall(html)))
        if paths:
            print(f"    api-looking paths: {len(paths)}")
            for p in paths[:20]:
                print(f"        {p}")

    # Widen: pull the bundles and mine them for endpoint names.
    if bundles:
        print()
        print("=" * 74)
        print("  BUNDLE ANALYSIS")
        print("=" * 74)
        seen = set()
        for base, src in bundles[:14]:
            if src.startswith("//"):
                url = "https:" + src
            elif src.startswith("http"):
                url = src
            elif src.startswith("/"):
                root = "/".join(base.split("/")[:3])
                url = root + src
            else:
                url = base.rstrip("/") + "/" + src
            if url in seen:
                continue
            seen.add(url)

            print()
            print(f"--- {url}")
            try:
                status, body = fetch(url, timeout=25)
            except Exception as exc:
                print(f"    failed: {type(exc).__name__}: {exc}")
                continue
            print(f"    HTTP {status}, {len(body):,} bytes")

            hosts_found = sorted(set(re.findall(
                r"https?://([A-Za-z0-9.-]+\.[A-Za-z]{2,})", body)))
            interesting = [h for h in hosts_found if "jetshr" in h or "jet" in h or "api" in h]
            if interesting:
                print(f"    hosts named in bundle: {len(interesting)}")
                for h in interesting[:25]:
                    print(f"        {h}")

            paths = sorted(set(APIPATH_RE.findall(body)))
            if paths:
                print(f"    api paths: {len(paths)}")
                for p in paths[:30]:
                    print(f"        {p}")


if __name__ == "__main__":
    main()
