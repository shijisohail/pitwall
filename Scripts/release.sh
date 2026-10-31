#!/usr/bin/env bash
# Developer ID sign -> DMG -> notarize -> staple -> checksum. See docs/RELEASING.md.
#
# Required:
#   SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#   BUNDLE_ID       your real reverse-DNS id (the OWNER placeholder is refused)
# Notarization credentials, one of:
#   NOTARY_PROFILE                                 a `xcrun notarytool store-credentials` keychain profile
#   NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER   an App Store Connect API key (what CI uses)
# Optional:
#   SKIP_NOTARIZE=1  sign and package only (for a dry run)
#   UNSIGNED=1       no Apple Developer account: ad-hoc signed DMG, no notarization
set -euo pipefail
cd "$(dirname "$0")/.."

# No Apple Developer account? UNSIGNED=1 builds the same DMG, ad-hoc signed and not notarized.
# It runs fine on the Mac that built it; on other Macs Gatekeeper asks the user to approve it (see README).
if [[ "${UNSIGNED:-0}" == "1" ]]; then
  export BUNDLE_ID="${BUNDLE_ID:-io.github.shijisohail.pitwall}"
  VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"; export VERSION
  echo "==> UNSIGNED build: ad-hoc signed, not notarized"
  Scripts/build.sh
  Scripts/make-dmg.sh
  ( cd dist && shasum -a 256 "Pitwall-$VERSION.dmg" > "Pitwall-$VERSION.dmg.sha256" )
  ls -la dist
  exit 0
fi

: "${SIGN_IDENTITY:?set SIGN_IDENTITY to your Developer ID Application identity}"
: "${BUNDLE_ID:?set BUNDLE_ID}"
if [[ "$BUNDLE_ID" == *OWNER* ]]; then echo "error: BUNDLE_ID still contains the OWNER placeholder" >&2; exit 1; fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then echo "error: refusing to release an ad-hoc signed build" >&2; exit 1; fi

export SIGN_IDENTITY BUNDLE_ID
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
export VERSION

Scripts/build.sh
Scripts/make-dmg.sh
DMG="dist/Pitwall-$VERSION.dmg"

echo "==> signing the disk image"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  echo "==> notarizing (this can take a few minutes)"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  else
    echo "error: set NOTARY_PROFILE, or NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER (or SKIP_NOTARIZE=1)" >&2; exit 1
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

( cd dist && shasum -a 256 "Pitwall-$VERSION.dmg" > "Pitwall-$VERSION.dmg.sha256" )
echo "==> done:"
ls -la dist
