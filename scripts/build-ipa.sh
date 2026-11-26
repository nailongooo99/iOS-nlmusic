#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-unsigned}"
BUNDLE_ID="${BUNDLE_ID:-com.nailong.music.ios}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]] || { echo "Invalid BUNDLE_ID"; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Invalid BUILD_NUMBER"; exit 2; }
[[ "$MODE" == unsigned || "$MODE" == ad-hoc || "$MODE" == development ]] || { echo "Unknown build mode"; exit 2; }
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
mkdir -p build dist
common=(-project NailongMusic.xcodeproj -scheme NailongMusic -configuration Release
        -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$PWD/build/DerivedData"
        "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" MARKETING_VERSION=1.0)
if [[ "$MODE" == unsigned ]]; then
  xcodebuild "${common[@]}" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
  APP="$PWD/build/DerivedData/Build/Products/Release-iphoneos/NailongMusic.app"
  test -f "$APP/Info.plist"
  rm -rf build/unsigned
  mkdir -p build/unsigned/Payload
  ditto "$APP" build/unsigned/Payload/NailongMusic.app
  (cd build/unsigned && /usr/bin/zip -qry "../../dist/NailongMusic-iOS-1.0-unsigned.ipa" Payload)
  echo "Unsigned IPA: NOT installable on stock iOS until validly signed."
else
  : "${APPLE_TEAM_ID:?Provide APPLE_TEAM_ID}"
  : "${PROFILE_NAME:?Provide PROFILE_NAME}"
  : "${PROFILE_UUID:?Provide PROFILE_UUID}"
  if [[ "$MODE" == ad-hoc ]]; then IDENTITY="Apple Distribution"; METHOD="release-testing"
  else IDENTITY="Apple Development"; METHOD="debugging"; fi
  ARCHIVE="$PWD/build/NailongMusic.xcarchive"
  rm -rf "$ARCHIVE" build/export
  xcodebuild "${common[@]}" -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Manual "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" "CODE_SIGN_IDENTITY=$IDENTITY" \
    "PROVISIONING_PROFILE_SPECIFIER=$PROFILE_NAME" archive
  export BUNDLE_ID APPLE_TEAM_ID PROFILE_UUID IDENTITY METHOD
  python3 - <<'PY'
import os, plistlib
with open("build/ExportOptions.plist","wb") as f:
    plistlib.dump({
        "method":os.environ["METHOD"],"signingStyle":"manual",
        "teamID":os.environ["APPLE_TEAM_ID"],"signingCertificate":os.environ["IDENTITY"],
        "provisioningProfiles":{os.environ["BUNDLE_ID"]:os.environ["PROFILE_UUID"]},
        "stripSwiftSymbols":True,"destination":"export","manageAppVersionAndBuildNumber":False,
    },f)
PY
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$PWD/build/export" -exportOptionsPlist "$PWD/build/ExportOptions.plist"
  ipa=$(find build/export -maxdepth 1 -name '*.ipa' -print -quit)
  test -n "$ipa"
  cp "$ipa" "dist/NailongMusic-iOS-1.0-$MODE.ipa"
  rm -rf build/verify
  mkdir -p build/verify
  unzip -q "dist/NailongMusic-iOS-1.0-$MODE.ipa" -d build/verify
  codesign --verify --deep --strict build/verify/Payload/NailongMusic.app
fi
python3 - <<'PY'
from pathlib import Path
import plistlib, zipfile, hashlib, os
for p in Path("dist").glob("*.ipa"):
    with zipfile.ZipFile(p) as z:
        info=plistlib.loads(z.read("Payload/NailongMusic.app/Info.plist"))
        assert info["CFBundleIdentifier"] == os.environ.get("BUNDLE_ID","com.nailong.music.ios"), info
        assert info["CFBundleShortVersionString"] == "1.0", info
        assert info["MinimumOSVersion"] == "16.0", info
        assert "audio" in info["UIBackgroundModes"]
        assert "Payload/NailongMusic.app/PrivacyInfo.xcprivacy" in z.namelist()
        assert "Payload/NailongMusic.app/lx-user-api-ios.js" in z.namelist()
        print(p.name, info["CFBundleIdentifier"], info["MinimumOSVersion"])
    with open(str(p)+".sha256","w") as f:
        f.write(hashlib.sha256(p.read_bytes()).hexdigest()+"  "+p.name+"\n")
PY
