#!/bin/bash
# Creates a stable, self-signed code-signing identity in your login keychain.
#
# Why: an ad-hoc signature (`codesign -s -`) changes on every rebuild, so macOS forgets
# the Full Disk Access grant each time you recompile. Signing with a *stable* identity
# keeps the same designated requirement across rebuilds, so you grant access only ONCE.
#
# Run this once. `build.sh` will automatically pick the identity up if it exists.
set -euo pipefail

NAME="Spaceful Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "✓ Identité déjà présente : « $NAME » — rien à faire."
  exit 0
fi

echo "▸ Création d'un certificat auto-signé « $NAME »…"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Self-signed cert with the codeSigning extended key usage.
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
  -subj "/CN=$NAME" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "keyUsage=critical,digitalSignature" >/dev/null 2>&1

# Use legacy PBE/MAC algorithms so macOS `security import` accepts the bundle
# (OpenSSL 3's modern PKCS12 MAC is rejected by the Security framework).
P12_PASS="spaceful"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout "pass:$P12_PASS" \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES >/dev/null 2>&1

# Import key + cert, pre-authorizing codesign to use the private key (no prompts).
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "✓ Identité créée."
echo "  Reconstruisez avec ./build.sh : le bundle sera signé avec « $NAME »,"
echo "  et l'Accès complet au disque accordé une fois restera valable après chaque rebuild."
