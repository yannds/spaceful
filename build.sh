#!/bin/bash
# Builds Spaceful and packages it into a double-clickable Spaceful.app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/Spaceful.app"
VERSION="0.1.0"
BUNDLE_ID="com.spaceful.app"

echo "▸ Compilation ($CONFIG)…"
cd "$ROOT"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Spaceful"
if [[ ! -f "$BIN" ]]; then
  echo "✗ Binaire introuvable: $BIN" >&2
  exit 1
fi

# Regenerate the app icon (.icns) from the pure-CoreGraphics generator if needed.
if [[ ! -f "$ROOT/Spaceful.icns" ]]; then
  echo "▸ Génération de l'icône…"
  swift "$ROOT/tools/make-icon.swift"
  iconutil -c icns "$ROOT/Spaceful.iconset" -o "$ROOT/Spaceful.icns"
fi

echo "▸ Empaquetage du bundle .app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Spaceful"
[[ -f "$ROOT/Spaceful.icns" ]] && cp "$ROOT/Spaceful.icns" "$APP/Contents/Resources/Spaceful.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Spaceful</string>
    <key>CFBundleDisplayName</key><string>Spaceful</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Spaceful</string>
    <key>CFBundleIconFile</key><string>Spaceful</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>Spaceful — visionneuse d'espace disque</string>
</dict>
</plist>
PLIST

# Signature. Default = ad-hoc, which always opens locally and keeps the Full Disk Access
# grant across launches (it only resets if the binary is recompiled). For a grant that
# also survives rebuilds, opt in explicitly with STABLE_SIGNING=1 ./build.sh after
# running tools/create-signing-identity.sh — note a self-signed app may require a
# one-time right-click ▸ Ouvrir the first time it is launched from the Finder.
SIGN_IDENTITY="Spaceful Self-Signed"
if [[ "${STABLE_SIGNING:-0}" == "1" ]] && security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "▸ Signature avec l'identité stable « $SIGN_IDENTITY » (opt-in)…"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
  echo "  (autorisation conservée après chaque rebuild ; 1er lancement : clic droit ▸ Ouvrir)"
else
  echo "▸ Signature ad-hoc…"
  codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (signature ad-hoc ignorée)"
fi

# Strip any quarantine flag so the local build opens without Gatekeeper friction.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✓ Terminé : $APP"
echo "  Lancer : open \"$APP\""
