#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
mkdir -p .local-signing
chmod 700 .local-signing
SIGNING_DIR="$(pwd)/.local-signing"
SIGNING_KEYCHAIN="$SIGNING_DIR/fold-menu.keychain-db"
if [ ! -f "$SIGNING_DIR/password" ]; then
  openssl rand -base64 -out "$SIGNING_DIR/password" 32
fi
SIGNING_PASSWORD="$(<"$SIGNING_DIR/password")"
if [ ! -f "$SIGNING_DIR/certificate.pem" ]; then
  openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config scripts/signing.cnf -keyout "$SIGNING_DIR/key.pem" -out "$SIGNING_DIR/certificate.pem"
  openssl pkcs12 -export -inkey "$SIGNING_DIR/key.pem" -in "$SIGNING_DIR/certificate.pem" \
    -out "$SIGNING_DIR/identity.p12" -passout "file:$SIGNING_DIR/password"
fi
if [ ! -f "$SIGNING_KEYCHAIN" ]; then
  security create-keychain -p "$SIGNING_PASSWORD" "$SIGNING_KEYCHAIN"
  security import "$SIGNING_DIR/identity.p12" -k "$SIGNING_KEYCHAIN" -P "$SIGNING_PASSWORD" -T /usr/bin/codesign
fi
security unlock-keychain -p "$SIGNING_PASSWORD" "$SIGNING_KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -s -k "$SIGNING_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null
if ! security verify-cert -c "$SIGNING_DIR/certificate.pem" -p codeSign >/dev/null 2>&1; then
  printf '%s\n' 'macOS may request authentication to trust this certificate for code signing in your user account.'
  security add-trusted-cert -r trustRoot -p codeSign -k "$SIGNING_KEYCHAIN" "$SIGNING_DIR/certificate.pem"
fi
printf '%s\n' 'Local identity prepared with user-scoped code-signing trust. Keep .local-signing private and persistent.'
