#!/bin/zsh
# Build + archive + ký ad-hoc (giữ entitlements sandbox) + export (cloud signing) + upload Mac App Store.
#   store/macstore/build_mac.sh <build_number>
set -e
BN=$1; [ -z "$BN" ] && { echo "usage: build_mac.sh <build>"; exit 1; }
cd "$(dirname $0)/../.."
OUT=build/macstore; rm -rf $OUT; mkdir -p $OUT
KEY=(-authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_V866A924D3.p8 -authenticationKeyID V866A924D3 -authenticationKeyIssuerID 69a6de95-6e8d-47e3-e053-5b8c7c11a4d1)

echo "== 1. flutter build (sinh xcconfig + DART_DEFINES; bước ký lỗi là bình thường)"
flutter build macos --release --dart-define-from-file=google_oauth.json --dart-define=GA4_API_SECRET="$(cat ~/.config/bcdcnt/ga4_api_secret)" || true

echo "== 2. archive không ký"
xcodebuild archive -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -archivePath $OUT/Runner.xcarchive DEVELOPMENT_TEAM=659VPB54MU CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO FLUTTER_BUILD_NUMBER=$BN | tail -3

echo "== 3. ký ad-hoc kèm entitlements"
APP=$(ls -d $OUT/Runner.xcarchive/Products/Applications/*.app)
for f in "$APP"/Contents/Frameworks/*; do codesign --force --sign - "$f"; done
codesign --force --sign - --entitlements macos/Runner/Release.entitlements "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -c app-sandbox

echo "== 4. export (cloud signing)"
cat > $OUT/export.plist <<P
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>method</key><string>app-store-connect</string><key>teamID</key><string>659VPB54MU</string>
<key>signingStyle</key><string>automatic</string><key>destination</key><string>export</string>
<key>manageAppVersionAndBuildNumber</key><false/></dict></plist>
P
xcodebuild -exportArchive -archivePath $OUT/Runner.xcarchive -exportOptionsPlist $OUT/export.plist -exportPath $OUT/export -allowProvisioningUpdates $KEY | tail -3
PKG=$(ls $OUT/export/*.pkg)

echo "== 5. upload"
xcrun altool --upload-app -t macos -f "$PKG" --apiKey V866A924D3 --apiIssuer 69a6de95-6e8d-47e3-e053-5b8c7c11a4d1 2>&1 | tail -5
