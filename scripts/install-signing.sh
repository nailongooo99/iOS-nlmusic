#!/usr/bin/env bash
set -euo pipefail
: "${APPLE_CERTIFICATE_P12_BASE64:?Missing APPLE_CERTIFICATE_P12_BASE64}"
: "${APPLE_CERTIFICATE_PASSWORD:?Missing APPLE_CERTIFICATE_PASSWORD}"
: "${APPLE_PROVISIONING_PROFILE_BASE64:?Missing APPLE_PROVISIONING_PROFILE_BASE64}"
: "${BUNDLE_ID:?Missing BUNDLE_ID}"
: "${RUNNER_TEMP:?Run in GitHub Actions or set RUNNER_TEMP}"
: "${GITHUB_ENV:?Run in GitHub Actions or set GITHUB_ENV}"
umask 077
P12="$RUNNER_TEMP/nailong-cert.p12"
PROFILE="$RUNNER_TEMP/nailong-profile.mobileprovision"
KEYCHAIN="$RUNNER_TEMP/nailong-signing.keychain-db"
DECODED="$RUNNER_TEMP/nailong-profile.plist"
cleanup_files(){ rm -f "$P12" "$PROFILE" "$DECODED"; }
trap cleanup_files EXIT
printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 -D > "$P12"
printf '%s' "$APPLE_PROVISIONING_PROFILE_BASE64" | base64 -D > "$PROFILE"
security cms -D -i "$PROFILE" > "$DECODED"
python3 - "$DECODED" <<'PY'
import os, plistlib, sys, datetime
p=plistlib.load(open(sys.argv[1],"rb"))
team=p["TeamIdentifier"][0]
uuid=p["UUID"]
name=p["Name"]
identifier=p["Entitlements"]["application-identifier"]
assert identifier == f"{team}.{os.environ['BUNDLE_ID']}", "Provisioning profile must match exact App ID"
assert p.get("ProvisionedDevices"), "Use a development or ad hoc profile with registered devices"
assert p["ExpirationDate"] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), "Expired provisioning profile"
get_task=p["Entitlements"].get("get-task-allow",False)
if os.environ.get("SIGN_MODE") == "development":
    assert get_task, "Use development profile"
elif os.environ.get("SIGN_MODE") == "ad-hoc":
    assert not get_task, "Use ad hoc distribution profile"
for value in [team,uuid,name]:
    assert "\n" not in value and "\r" not in value
with open(os.environ["GITHUB_ENV"],"a") as f:
    f.write(f"APPLE_TEAM_ID={team}\nPROFILE_UUID={uuid}\nPROFILE_NAME={name}\n")
print("Provisioning profile validated (registered devices, exact bundle ID, non-expired).")
PY
PASSWORD=$(openssl rand -hex 32)
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$P12" -P "$APPLE_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
security find-identity -v -p codesigning "$KEYCHAIN"
UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$DECODED")
# Xcode 16+ profile directory; retain legacy path for compatibility.
mkdir -p "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PROFILE" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$UUID.mobileprovision"
cp "$PROFILE" "$HOME/Library/MobileDevice/Provisioning Profiles/$UUID.mobileprovision"
