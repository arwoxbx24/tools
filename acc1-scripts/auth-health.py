#!/usr/bin/env python3
"""Validate Google and AssemblyAI credentials without exposing their values."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def result(status, reason, auth=None):
    value = {"status": status, "reason": reason}
    if auth:
        value["auth"] = auth
    return value


def request_json(url, *, headers=None, data=None):
    request = urllib.request.Request(url, headers=headers or {}, data=data)
    with urllib.request.urlopen(request, timeout=15) as response:
        return response.status, json.load(response)


def candidates(root):
    assembly = []
    oauth = []
    service_accounts = []
    if not root.is_dir():
        return assembly, oauth, service_accounts
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.stat().st_size > 1_000_000:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            payload = None
        if isinstance(payload, dict):
            payload = payload.get("installed") or payload.get("web") or payload
            if payload.get("ASSEMBLYAI_API_KEY"):
                assembly.append(payload["ASSEMBLYAI_API_KEY"])
            if all(payload.get(key) for key in ("client_id", "refresh_token")):
                oauth.append(payload)
            if payload.get("type") == "service_account" and all(
                payload.get(key) for key in ("client_email", "private_key")
            ):
                service_accounts.append(payload)
            continue
        for line in text.splitlines():
            name, separator, value = line.partition("=")
            if separator and name.removeprefix("export ").strip() == "ASSEMBLYAI_API_KEY":
                value = value.strip().strip("'\"")
                if value:
                    assembly.append(value)
    return assembly, oauth, service_accounts


def check_assembly(keys):
    if not keys:
        return result("FAIL", "not_found")
    try:
        status, _ = request_json(
            "https://api.assemblyai.com/v2/transcript?limit=1",
            headers={"authorization": keys[0]},
        )
        return result("PASS", "authenticated", "api_key") if status == 200 else result("FAIL", "rejected", "api_key")
    except urllib.error.HTTPError:
        return result("FAIL", "rejected", "api_key")
    except Exception:
        return result("FAIL", "network_error", "api_key")


def check_google(oauth, service_accounts):
    for token in oauth:
        data = urllib.parse.urlencode({
            "grant_type": "refresh_token",
            "client_id": token["client_id"],
            "client_secret": token.get("client_secret", ""),
            "refresh_token": token["refresh_token"],
        }).encode()
        try:
            status, payload = request_json("https://oauth2.googleapis.com/token", data=data)
            if status == 200 and payload.get("access_token"):
                return result("PASS", "authenticated", "oauth")
        except Exception:
            pass
    for account in service_accounts:
        try:
            import jwt
            now = int(time.time())
            assertion = jwt.encode({
                "iss": account["client_email"],
                "scope": "https://www.googleapis.com/auth/drive.readonly",
                "aud": "https://oauth2.googleapis.com/token",
                "iat": now,
                "exp": now + 3600,
            }, account["private_key"], algorithm="RS256")
            data = urllib.parse.urlencode({
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": assertion,
            }).encode()
            status, payload = request_json("https://oauth2.googleapis.com/token", data=data)
            if status == 200 and payload.get("access_token"):
                return result("PASS", "authenticated", "service_account")
        except Exception:
            pass
    if not oauth and not service_accounts:
        return result("FAIL", "not_found")
    return result("FAIL", "rejected")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--secrets-root", type=Path, default=Path("/root/workspaces/secrets"))
    args = parser.parse_args()
    assembly, oauth, service_accounts = candidates(args.secrets_root)
    with ThreadPoolExecutor(max_workers=2) as pool:
        google = pool.submit(check_google, oauth, service_accounts)
        assemblyai = pool.submit(check_assembly, assembly)
        payload = {
            "google_credentials": google.result(),
            "assemblyai_credentials": assemblyai.result(),
        }
    print(json.dumps(payload, sort_keys=True))
    return 0 if all(item["status"] == "PASS" for item in payload.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
