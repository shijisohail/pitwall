#!/usr/bin/env bash
# One-time setup: create a local, self-signed code-signing identity ("Pitwall Local Signing") so the builds you make on
# this Mac keep the SAME identity from build to build.
#
# Why: an ad-hoc build is identified by the hash of its binary, which changes on every rebuild. macOS then treats each
# build as a brand-new app and asks again for Documents, Downloads, network volumes... With a stable identity macOS
# remembers your answers. Scripts/build.sh uses this identity automatically once it exists.
#
# What it changes: it adds a certificate and its private key to your LOGIN keychain and trusts that certificate for
# code signing for your user. Anyone with access to your login keychain could therefore sign code your Mac treats as
# trusted-for-you, so it is meant for your own development Mac only. To undo it, delete "Pitwall Local Signing" in
# Keychain Access. It is not a distribution certificate (see docs/RELEASING.md for that).
#
# Safe to re-run: if a previous run imported the certificate but trust didn't complete, this repairs that.
set -euo pipefail

NAME="Pitwall Local Signing"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
OPENSSL=/usr/bin/openssl          # macOS's own LibreSSL: its PKCS#12 output is what `security import` expects

have_any()   { security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "\"$NAME\""; }
have_valid() { security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "\"$NAME\""; }

trust_cert() {   # $1 = PEM file
  echo "Trusting it for code signing (macOS will ask for your password)..."
  if ! security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$1"; then
    echo "error: macOS didn't accept the trust change (cancelled?). Nothing else was changed." >&2
    echo "       Run this script again to retry, or in Keychain Access open \"$NAME\" > Trust > Code Signing > Always Trust." >&2
    return 1
  fi
}

finish() {
  if have_valid; then
    echo
    echo "Done. \"$NAME\" is ready. Rebuild with Scripts/build.sh; the first build may ask to let codesign use the key (choose Always Allow)."
    echo "macOS will ask for folder access one more time for that build, then remember your answers across rebuilds."
  else
    echo "error: \"$NAME\" is in the keychain but still isn't valid for code signing. Open Keychain Access, find it, and set Trust > Code Signing to Always Trust." >&2
    exit 1
  fi
}

if have_valid; then
  echo "\"$NAME\" already exists and is trusted. Nothing to do; Scripts/build.sh will use it."
  exit 0
fi

dir="$(mktemp -d)"; trap 'rm -rf "$dir"' EXIT

if have_any; then
  echo "\"$NAME\" is in your keychain but isn't trusted for code signing yet (an earlier run was probably interrupted)."
  read -r -p "Re-apply trust now? [y/N] " yn
  [[ "$yn" == [yY]* ]] || { echo "Cancelled. Nothing was changed."; exit 1; }
  security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$dir/cert.pem"
  trust_cert "$dir/cert.pem"
  finish; exit 0
fi

cat <<MSG
This will:
  1. create a self-signed code-signing certificate named "$NAME" (valid 10 years),
  2. add it, with its private key, to your login keychain, and
  3. trust it for code signing, for your user only (macOS asks for your password).

MSG
read -r -p "Continue? [y/N] " yn
[[ "$yn" == [yY]* ]] || { echo "Cancelled. Nothing was changed."; exit 1; }

pass="$($OPENSSL rand -hex 16)"
cat > "$dir/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

$OPENSSL req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/openssl.cnf" -keyout "$dir/key.pem" -out "$dir/cert.pem"
$OPENSSL pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$NAME" -out "$dir/id.p12" -passout "pass:$pass"

if ! security import "$dir/id.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign; then
  echo "error: couldn't import the certificate into $KEYCHAIN." >&2
  exit 1
fi
trust_cert "$dir/cert.pem"
finish
