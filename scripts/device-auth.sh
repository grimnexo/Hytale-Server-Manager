#!/usr/bin/env bash
set -euo pipefail

INSTANCE_DIR=${1:-"$(pwd)"}
OUT_DIR="$INSTANCE_DIR/.auth"
PYTHON_BIN=${PYTHON_BIN:-python3}
HYAUTH_CLIENT_ID=${HYAUTH_CLIENT_ID:-hytale-server}
HYAUTH_SCOPE=${HYAUTH_SCOPE:-openid offline auth:server}
HYAUTH_OAUTH_BASE=${HYAUTH_OAUTH_BASE:-https://oauth.accounts.hytale.com}
HYAUTH_ACCOUNTS_BASE=${HYAUTH_ACCOUNTS_BASE:-https://accounts.hytale.com}
HYAUTH_ACCOUNT_DATA_BASE=${HYAUTH_ACCOUNT_DATA_BASE:-https://account-data.hytale.com}
HYAUTH_SESSIONS_BASE=${HYAUTH_SESSIONS_BASE:-https://sessions.hytale.com}

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "python3 is required for device-auth.sh" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

cat <<EOF
Before continuing, make sure you can log in to your Hytale account:
- Login: https://accounts.hytale.com/
- Register: https://accounts.hytale.com/registration

This script will start the OAuth device flow and prompt you with a device code.
EOF

"$PYTHON_BIN" - "$OUT_DIR" "$HYAUTH_CLIENT_ID" "$HYAUTH_SCOPE" "$HYAUTH_OAUTH_BASE" "$HYAUTH_ACCOUNTS_BASE" "$HYAUTH_ACCOUNT_DATA_BASE" "$HYAUTH_SESSIONS_BASE" <<'PY'
import json
import sys
import time
import urllib.parse
import urllib.request
import urllib.error

out_dir = sys.argv[1]
client_id = sys.argv[2]
scope = sys.argv[3]
oauth_base = sys.argv[4].rstrip("/")
accounts_base = sys.argv[5].rstrip("/")
account_data_base = sys.argv[6].rstrip("/")
sessions_base = sys.argv[7].rstrip("/")

def post_form(url, data):
    body = urllib.parse.urlencode(data).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
            "User-Agent": "hytale-server-device-auth/0.1",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def get_json(url, headers=None):
    hdrs = {"Accept": "application/json", "User-Agent": "hytale-server-device-auth/0.1"}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, headers=hdrs)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def post_json(url, payload, headers=None):
    body = json.dumps(payload).encode("utf-8")
    hdrs = {"Content-Type": "application/json", "Accept": "application/json", "User-Agent": "hytale-server-device-auth/0.1"}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, data=body, headers=hdrs)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

try:
    device = post_form(
        f"{oauth_base}/oauth2/device/auth",
        {"client_id": client_id, "scope": scope},
    )
except urllib.error.HTTPError as exc:
    body = exc.read().decode("utf-8")
    raise SystemExit(
        f"Device auth request failed ({exc.code}).\n"
        f"Response: {body}\n"
        "If you see 403, ensure the device auth endpoints are reachable and that "
        "your account has access to Hytale services."
    )

verification_uri = device.get("verification_uri")
verification_uri_complete = device.get("verification_uri_complete")
user_code = device.get("user_code")
device_code = device.get("device_code")
interval = int(device.get("interval", 5))
expires_in = int(device.get("expires_in", 900))

print("\nDEVICE AUTHORIZATION")
if verification_uri_complete:
    print(f"Visit: {verification_uri_complete}")
else:
    print(f"Visit: {verification_uri or accounts_base + '/device'}")
    print(f"Enter code: {user_code}")
print(f"Expires in: {expires_in} seconds\n")

token = None
start = time.time()
while time.time() - start < expires_in:
    try:
        token = post_form(
            f"{oauth_base}/oauth2/token",
            {
                "client_id": client_id,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": device_code,
            },
        )
    except urllib.error.HTTPError as exc:
        data = exc.read().decode("utf-8")
        try:
            payload = json.loads(data)
        except json.JSONDecodeError:
            payload = {"error": data}
        if payload.get("error") in ("authorization_pending", "slow_down"):
            time.sleep(interval)
            continue
        raise

    if "access_token" in token:
        break
    time.sleep(interval)

if not token or "access_token" not in token:
    raise SystemExit("Authorization did not complete before expiration.")

access_token = token["access_token"]
refresh_token = token.get("refresh_token")

profiles = get_json(
    f"{account_data_base}/my-account/get-profiles",
    headers={"Authorization": f"Bearer {access_token}"},
)
profile_list = profiles.get("profiles", [])
if not profile_list:
    raise SystemExit("No profiles found for this account.")

if len(profile_list) == 1:
    profile = profile_list[0]
else:
    print("Available profiles:")
    for idx, profile in enumerate(profile_list, 1):
        print(f"{idx}) {profile.get('username')} ({profile.get('uuid')})")
    while True:
        choice = input("Select profile number: ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(profile_list):
            profile = profile_list[int(choice) - 1]
            break

session = post_json(
    f"{sessions_base}/game-session/new",
    {"uuid": profile.get("uuid")},
    headers={"Authorization": f"Bearer {access_token}"},
)

created_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

payload = {
    "access_token": access_token,
    "refresh_token": refresh_token,
    "created_at": created_at,
    "expires_in": token.get("expires_in"),
    "profile": profile,
    "session": session,
}

with open(f"{out_dir}/tokens.json", "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)

with open(f"{out_dir}/export.env", "w", encoding="utf-8") as handle:
    handle.write(f"HYTALE_SERVER_SESSION_TOKEN={session.get('sessionToken','')}\n")
    handle.write(f"HYTALE_SERVER_IDENTITY_TOKEN={session.get('identityToken','')}\n")
    handle.write(f"HYTALE_SERVER_OWNER_UUID={profile.get('uuid','')}\n")

print("\nTokens written to:")
print(f"  {out_dir}/tokens.json")
print(f"  {out_dir}/export.env")
print("\nNote: Game sessions expire in 1 hour; you'll need to refresh tokens for long-running servers.")
PY
