#!/usr/bin/env python3
"""
Route-table interrogation for a public API.

Sends unauthenticated requests to a bounded set of plausible routes that follow
the vocabulary recovered from the client, and reads the status code as the
answer:

    404  -> no such route
    401 / 403 -> route exists and wants credentials
    400 / 422 -> route exists and wants a body
    405  -> route exists, different method

That is ordinary documentation discovery against a public endpoint. No
credentials are guessed, no payload is sent, nothing is brute forced.
"""
import json
import ssl
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.gojet.app"
UA = "Mozilla/5.0 (Linux; Android 14) okhttp/4.12.0"

ROUTES = [
    "/",
    "/api",
    "/api/v1",
    "/api/v1/",
    "/api/v1/auth",
    "/api/v1/auth/token",
    "/api/v1/auth/token/refresh",
    "/api/v1/auth/login",
    "/api/v1/auth/logout",
    "/api/v1/auth/sms",
    "/api/v1/auth/code",
    "/api/v1/auth/otp",
    "/api/v1/auth/verify",
    "/api/v1/auth/phone",
    "/api/v1/auth/register",
    "/api/v1/user",
    "/api/v1/users/me",
    "/api/v1/profile",
    "/api/v1/config",
    "/api/v1/settings",
    "/api/v1/version",
    "/api/v1/health",
    "/api/v1/vehicles",
    "/api/v1/vehicles/nearby",
    "/api/v1/scooters",
    "/api/v1/rides",
    "/api/v1/orders",
    "/api/v1/rides/active",
    "/api/v1/payments",
    "/api/v1/balance",
]


def ctx():
    return ssl.create_default_context()


def probe(path, method="GET"):
    url = BASE + path
    req = urllib.request.Request(url, method=method, headers={
        "User-Agent": UA,
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=15, context=ctx()) as r:
            body = r.read(600).decode("utf-8", "replace")
            return r.status, body, dict(r.headers)
    except urllib.error.HTTPError as exc:
        try:
            body = exc.read(600).decode("utf-8", "replace")
        except Exception:
            body = ""
        return exc.code, body, dict(exc.headers)
    except Exception as exc:
        return None, f"{type(exc).__name__}: {exc}", {}


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

    print("=" * 88)
    print(f"  ROUTE INTERROGATION — {BASE}")
    print("=" * 88)
    print(f"  {'path':<38} {'GET':>5}  {'POST':>5}   note")
    print("-" * 88)

    live = []
    for path in ROUTES:
        g, gbody, gheaders = probe(path, "GET")
        time.sleep(0.4)
        p, pbody, _ = probe(path, "POST")
        time.sleep(0.4)

        note = ""
        for status, body in ((g, gbody), (p, pbody)):
            if status in (401, 403):
                note = "EXISTS — wants credentials"
                break
            if status in (400, 422):
                note = "EXISTS — wants a body"
                break
            if status == 405:
                note = "EXISTS — wrong method"
                break
            if status == 200:
                note = "OPEN"
                break
        if g == 200 or p == 200 or (note and "wants credentials" in note) or (note and "wants a body" in note):
            live.append((path, g, p, note))

        print(f"  {path:<38} {str(g):>5}  {str(p):>5}   {note}")

    print()
    print("=" * 88)
    print("  ROUTES THAT ANSWERED")
    print("=" * 88)
    if not live:
        print("  none — every candidate returned 404")
    for path, g, p, note in live:
        print(f"  {path:<40} GET={g} POST={p}  {note}")


if __name__ == "__main__":
    main()
