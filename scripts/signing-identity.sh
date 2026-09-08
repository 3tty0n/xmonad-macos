#!/bin/bash
# Create, or report, a stable local code signing identity.
#
# Ad-hoc signatures (codesign -s -) identify an app to TCC by its code
# directory hash, which changes on every build, so the Accessibility grant is
# lost whenever the native app is rebuilt. A signature made with a persistent
# certificate is identified by that certificate instead, and the grant
# survives rebuilds.
#
# Trusting the certificate needs your login password, so this is a deliberate
# one-time command. `--if-ready` is the build's non-interactive probe: it
# prints the name only when the identity is already usable.
set -euo pipefail
NAME="XMonadMac Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

have_identity() {
  /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null |
    grep -qF "$NAME"
}
have_certificate() {
  /usr/bin/security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1
}

if have_identity; then printf '%s\n' "$NAME"; exit 0; fi
if [ "${1:-}" = --if-ready ]; then exit 1; fi

if ! have_certificate; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
  # macOS refuses a PKCS#12 with an empty password: its MAC check fails.
  PW="$(/usr/bin/openssl rand -hex 16)"
  /usr/bin/openssl pkcs12 -export -out "$TMP/id.p12" -name "$NAME" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout "pass:$PW" >/dev/null 2>&1
  /usr/bin/security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PW" \
    -T /usr/bin/codesign -A >/dev/null
fi

# Trust whatever is in the keychain, which may be a certificate an earlier,
# interrupted run imported but never trusted.
PEM="$(mktemp)"
trap 'rm -f "$PEM"' EXIT
/usr/bin/security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$PEM"
echo "Trusting $NAME for code signing." >&2
echo "macOS will ask for your login password." >&2
/usr/bin/security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$PEM"
have_identity || { echo "Could not create $NAME." >&2; exit 1; }
printf '%s\n' "$NAME"
