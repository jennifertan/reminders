#!/bin/sh
# Archives Ringlet and uploads it to TestFlight, the same way as replanta: automatic signing
# with team 2C3UFXPB4P and ExportOptions.plist (method app-store-connect, destination upload).
#
# Run on a Mac with Xcode, from the repo root:   ./scripts/testflight.sh
#
# Xcode uses the Apple ID signed in under Xcode > Settings > Accounts. To use an App Store Connect
# API key instead (for example on a build server), set ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID.
# The build number is bumped automatically on upload (manageAppVersionAndBuildNumber).
set -eu

cd "$(dirname "$0")/.."
ARCHIVE=build/Ringlet.xcarchive

AUTH=""
if [ -n "${ASC_KEY_PATH:-}" ]; then
  AUTH="-authenticationKeyPath $ASC_KEY_PATH -authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID"
fi

rm -rf "$ARCHIVE" build/export

# shellcheck disable=SC2086
xcodebuild archive \
  -project Ringlet.xcodeproj \
  -scheme Ringlet \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates $AUTH

# shellcheck disable=SC2086
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates $AUTH

echo "Uploaded. The build shows up in App Store Connect > TestFlight after Apple finishes processing it (usually 5 to 15 minutes)."
