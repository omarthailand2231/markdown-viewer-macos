#!/usr/bin/env bash
# Creates a self-signed code-signing identity in its own keychain (once).
# Signing every build with the same certificate keeps macOS privacy grants
# (Screen Recording) across rebuilds; ad-hoc signatures change on every build.
set -euo pipefail

NAME="Local Code Signing"
KEYCHAIN="$HOME/Library/Keychains/dev-signing.keychain-db"
PWFILE="$HOME/.config/dev-signing/keychain-password"

if [[ -f "$KEYCHAIN" && -f "$PWFILE" ]]; then
  security unlock-keychain -p "$(cat "$PWFILE")" "$KEYCHAIN"
  if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    exit 0
  fi
fi

mkdir -p "$(dirname "$PWFILE")"
if [[ ! -f "$PWFILE" ]]; then
  (umask 077 && openssl rand -hex 24 > "$PWFILE")
fi
PW="$(cat "$PWFILE")"

if [[ ! -f "$KEYCHAIN" ]]; then
  security create-keychain -p "$PW" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN" # no auto-lock
fi
security unlock-keychain -p "$PW" "$KEYCHAIN"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" \
  -passout pass:"$PW" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PW" -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a keychain prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KEYCHAIN" >/dev/null
echo "Created signing identity \"$NAME\" in $KEYCHAIN"
