#!/usr/bin/env bash
# Builds build/Pitwall.app (universal, hardened-runtime signed). No Xcode project needed.
#
#   Scripts/build.sh [run]
#
# Environment (all optional):
#   VERSION        defaults to the contents of ./VERSION
#   BUILD_NUMBER   CFBundleVersion; defaults to the git commit count (or 1)
#   BUNDLE_ID      defaults to a placeholder: set it to your reverse-DNS id before releasing
#   PITWALL_REPO_URL shown in the Help menu (hidden while it contains OWNER)
#   ARCHS          space separated, default "arm64 x86_64"
#   SIGN_IDENTITY  codesign identity. Default: "Pitwall Local Signing" if Scripts/setup-local-signing.sh created it,
#                  else "-" (ad-hoc, fine for local use only; macOS re-asks for folder access on every rebuild)
#   SDK            macOS SDK path; auto-detected (see below)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
BUNDLE_ID="${BUNDLE_ID:-io.github.shijisohail.pitwall}"
PITWALL_REPO_URL="${PITWALL_REPO_URL:-https://github.com/shijisohail/pitwall}"
ARCHS="${ARCHS:-arm64 x86_64}"
# Default identity: a stable local one if Scripts/setup-local-signing.sh created it (so macOS keeps your folder
# permissions across rebuilds), else ad-hoc.
LOCAL_ID="Pitwall Local Signing"
IDENTITY_CHOSEN_BY_CALLER="${SIGN_IDENTITY:+1}"     # a release script passes its own identity; don't nag it
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  # Capture the lists first: `security ... | grep -q` under pipefail can fail with SIGPIPE when grep exits early.
  valid_ids="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  any_ids="$(security find-identity -p codesigning 2>/dev/null || true)"
  if grep -qF "\"$LOCAL_ID\"" <<<"$valid_ids"; then
    SIGN_IDENTITY="$LOCAL_ID"
  else
    SIGN_IDENTITY="-"
    # Imported but not trusted yet (setup was cancelled at the password step): codesign can't use it.
    if grep -qF "\"$LOCAL_ID\"" <<<"$any_ids"; then
      echo "warning: \"$LOCAL_ID\" is in your keychain but isn't trusted for code signing yet. Run Scripts/setup-local-signing.sh again and answer y to finish." >&2
    fi
  fi
fi

# SDK: use Xcode's when it works. A bare Command Line Tools install may default to an SDK newer than its
# compiler ("SDK is built with Swift X, compiler is Y"), so fall back to its pinned macOS 26 SDK.
if [[ -z "${SDK:-}" ]]; then
  clt26=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
  if ! xcodebuild -version >/dev/null 2>&1 && [[ -d "$clt26" ]]; then SDK="$clt26"; else SDK="$(xcrun --show-sdk-path)"; fi
fi

echo "==> Pitwall $VERSION ($BUILD_NUMBER)  bundle id: $BUNDLE_ID  archs: $ARCHS  sdk: $SDK"

APP=build/Pitwall.app
mkdir -p build
rm -rf "$APP" build/slices
mkdir -p build/slices "$APP/Contents/MacOS" "$APP/Contents/Resources"

slices=()
for arch in $ARCHS; do
  echo "==> compiling $arch"
  swiftc -sdk "$SDK" -swift-version 5 -parse-as-library -O -whole-module-optimization \
    -target "$arch-apple-macos26.0" \
    Sources/Pitwall/*.swift Sources/Pitwall/Views/*.swift \
    -o "build/slices/Pitwall-$arch"
  slices+=("build/slices/Pitwall-$arch")
done
if [[ ${#slices[@]} -gt 1 ]]; then lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/Pitwall"; else cp "${slices[0]}" "$APP/Contents/MacOS/Pitwall"; fi

sed -e "s|@VERSION@|$VERSION|g" -e "s|@BUILD@|$BUILD_NUMBER|g" -e "s|@BUNDLE_ID@|$BUNDLE_ID|g" \
    -e "s|@REPO_URL@|$PITWALL_REPO_URL|g" -e "s|@YEAR@|$(date +%Y)|g" \
    Resources/Info.plist.in > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> signing (${SIGN_IDENTITY/#-/ad-hoc})"
if [[ "$SIGN_IDENTITY" == "-" || "$SIGN_IDENTITY" == "$LOCAL_ID" ]]; then ts="--timestamp=none"; else ts="--timestamp"; fi
if ! codesign --force --options runtime $ts --entitlements Resources/Pitwall.entitlements --sign "$SIGN_IDENTITY" "$APP"; then
  if [[ "$SIGN_IDENTITY" == "$LOCAL_ID" ]]; then
    # e.g. a locked keychain or an SSH/CI session that can't show the key-access prompt: don't fail the build over it.
    echo "warning: couldn't sign with \"$LOCAL_ID\"; falling back to an ad-hoc signature (macOS will re-ask for folder access)" >&2
    SIGN_IDENTITY="-"
    codesign --force --options runtime --timestamp=none --entitlements Resources/Pitwall.entitlements --sign - "$APP"
  else
    exit 1
  fi
fi
codesign --verify --strict --verbose=1 "$APP"

if [[ "$SIGN_IDENTITY" == "-" && -z "$IDENTITY_CHOSEN_BY_CALLER" ]]; then
  cat >&2 <<'NOTE'

note: this build is ad-hoc signed. macOS identifies an ad-hoc build by its hash, which changes on every rebuild, so it
      treats each build as a new app: it forgets the folder permissions (Documents, Desktop, Downloads...) and Full Disk
      Access you gave the previous one, and asks again. Run Scripts/setup-local-signing.sh once to stop that.
NOTE
fi

echo "==> built $APP"
[[ "${1:-}" == "run" ]] && open "$APP"
exit 0
