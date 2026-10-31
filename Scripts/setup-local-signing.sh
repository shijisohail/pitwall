#!/usr/bin/env bash
# One-time setup: create a local, self-signed code-signing identity ("Pitwall Local Signing") so the builds you make on
# this Mac keep the SAME identity from build to build.
#
# Why: an ad-hoc build is identified by the hash of its binary, which changes on every rebuild. macOS then treats each
# build as a brand-new app and asks again for Documents, Downloads, network volumes... With a stable identity macOS
# remembers your answers. Scripts/build.sh uses this identity automatically once it exists.
#
# This only affects builds made on this Mac. It is not a distribution certificate (see docs/RELEASING.md for that).
# It adds a certificate to your login keychain and trusts it for code signing for your user, which macOS will ask you
# to confirm with your password.
set -euo pipefail

NAME="Pitwall Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "\"$NAME\" already exists. Nothing to do. Scripts/build.sh will use it."
  exit 0
fi

cat <<MSG
This will:
  1. create a self-signed code-signing certificate named "$NAME" (valid 10 years),
  2. add it to your login keychain, and
  3. trust it for code signing, for your user only (macOS asks for your password).

MSG
read -r -p "Continue? [y/N] " yn
[[ "$yn" == [yY]* ]] || { echo "Cancelled. Nothing was changed."; exit 1; }

dir="$(mktemp -d)"; trap 'rm -rf "$dir"' EXIT
pass="$(openssl rand -hex 16)"

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

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/openssl.cnf" \
  -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$NAME" \
  -out "$dir/id.p12" -passout "pass:$pass" 2>/dev/null

security import "$dir/id.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$dir/cert.pem"

echo
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "Done. \"$NAME\" is ready. Rebuild with Scripts/build.sh; the first build may ask to let codesign use the key (choose Always Allow)."
  echo "macOS will ask for folder access one more time for the next build, then remember it across rebuilds."
else
  echo "The certificate was imported but isn't listed as valid yet. Open Keychain Access, find \"$NAME\", and set Trust > Code Signing to Always Trust."
  exit 1
fi
