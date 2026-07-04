#!/bin/bash
set -e

APP_NAME="MT3K Mac Tools"
BUNDLE_ID="com.mt3k.mac-tools"
VERSION="1.0"
BUILD_CONFIG="${1:-release}"
INSTALL_TO_APPLICATIONS="${MT3K_INSTALL_TO_APPLICATIONS:-1}"

if [ "$BUILD_CONFIG" = "release" ]; then
  BUILD_DIR=".build/release"
  echo "→ Compilando release..."
  swift build -c release --product mt3k-mac-tools
  swift build -c release --product mt3k-battery-helper
else
  BUILD_DIR=".build/debug"
  echo "→ Compilando debug..."
  swift build --product mt3k-mac-tools
  swift build --product mt3k-battery-helper
fi

APP_PATH="dist/${APP_NAME}.app"
echo "→ Empaquetando .app en $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources/scripts"

cp "$BUILD_DIR/mt3k-mac-tools" "$APP_PATH/Contents/MacOS/${APP_NAME}"
cp "$BUILD_DIR/mt3k-battery-helper" "$APP_PATH/Contents/Resources/mt3k-battery-helper"
cp scripts/*.sh "$APP_PATH/Contents/Resources/scripts/"
chmod +x "$APP_PATH/Contents/Resources/scripts/"*.sh
chmod +x "$APP_PATH/Contents/Resources/mt3k-battery-helper"
cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/"
# Sprites & menu bar icon (PNG @1x/@2x/@3x para retina).
for png in Resources/*.png; do
    [ -e "$png" ] && cp "$png" "$APP_PATH/Contents/Resources/"
done

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>MT3K Flow usa el micrófono solo mientras pruebas o grabas dictado.</string>
    <key>NSInputMonitoringUsageDescription</key><string>MT3K Flow necesita Input Monitoring para detectar la hotkey global de dictado.</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSQuitAlwaysKeepsWindows</key><false/>
    <key>NSHumanReadableCopyright</key><string>MT3K © $(date +%Y)</string>
</dict>
</plist>
EOF

ENTITLEMENTS_PATH="$APP_PATH/Contents/Resources/MT3K.entitlements"
cat > "$ENTITLEMENTS_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
EOF

SIGN_IDENTITY="${MT3K_CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi

if [ -n "$SIGN_IDENTITY" ]; then
  echo "→ Firmando con Developer ID: $SIGN_IDENTITY"
  codesign --force --options runtime --timestamp --identifier "${BUNDLE_ID}.battery-helper" --sign "$SIGN_IDENTITY" "$APP_PATH/Contents/Resources/mt3k-battery-helper"
  # No --deep on the app: it would re-sign the pre-signed helper with the app's identifier,
  # stripping its own TeamIdentifier. The helper is already signed explicitly above.
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS_PATH" --identifier "$BUNDLE_ID" --sign "$SIGN_IDENTITY" "$APP_PATH"

  # Notarización opcional: sólo corre si existe el perfil de notarytool en Keychain.
  # Crear una vez con:
  #   xcrun notarytool store-credentials mt3k-notary --apple-id <apple-id> --team-id <your-team-id>
  NOTARY_PROFILE="${MT3K_NOTARY_PROFILE:-mt3k-notary}"
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "→ Notarizando con perfil '$NOTARY_PROFILE' (puede tardar unos minutos)..."
    NOTARY_ZIP="dist/${APP_NAME// /-}-notarize.zip"
    ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
    if xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
      xcrun stapler staple "$APP_PATH"
      echo "✓ Notarizado y stapled."
    else
      echo "✗ Notarización falló; el .app queda firmado pero sin notarizar." >&2
    fi
    rm -f "$NOTARY_ZIP"
  else
    echo "  (Notarización omitida: no hay perfil '$NOTARY_PROFILE' en Keychain.)"
  fi
else
  echo "→ Firmando ad-hoc (sin Developer ID instalado; TCC puede pedir permisos tras cada rebuild)"
  codesign --force --deep --entitlements "$ENTITLEMENTS_PATH" --identifier "$BUNDLE_ID" --sign - "$APP_PATH" 2>/dev/null || true
fi

if [ "$INSTALL_TO_APPLICATIONS" = "1" ]; then
  APPLICATIONS_PATH="/Applications/${APP_NAME}.app"
  echo "→ Actualizando $APPLICATIONS_PATH"
  rm -rf "$APPLICATIONS_PATH"
  cp -R "$APP_PATH" "$APPLICATIONS_PATH"
  xattr -dr com.apple.quarantine "$APPLICATIONS_PATH" 2>/dev/null || true
  codesign --verify --deep --strict "$APPLICATIONS_PATH"
fi

echo "✓ Listo: $APP_PATH"
echo "  Tamaño: $(du -sh "$APP_PATH" | cut -f1)"
echo "  Para correr: open '$APP_PATH'"
if [ "$INSTALL_TO_APPLICATIONS" = "1" ]; then
  echo "  Instalado: open '/Applications/${APP_NAME}.app'"
fi
