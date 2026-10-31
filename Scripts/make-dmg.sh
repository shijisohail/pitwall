#!/usr/bin/env bash
# Packs build/Pitwall.app into dist/Pitwall-<version>.dmg (drag-to-Applications layout).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
APP=build/Pitwall.app
DMG="dist/Pitwall-$VERSION.dmg"
[[ -d "$APP" ]] || { echo "error: $APP not found; run Scripts/build.sh first" >&2; exit 1; }

mkdir -p dist
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$APP" "$stage/Pitwall.app"
ln -s /Applications "$stage/Applications"
rm -f "$DMG"
hdiutil create -volname "Pitwall $VERSION" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "==> $DMG"
