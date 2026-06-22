#!/usr/bin/env bash
set -euo pipefail

# Build and package DAL SEEN for macOS.
# Requires: MACOS_CODESIGN_IDENTITY (Developer ID Application: ...)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(grep '^version' "$ROOT/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')}"
APP_NAME="DAL SEEN"
APP="$ROOT/flutter/build/macos/Build/Products/Release/${APP_NAME}.app"
IDENTITY="${MACOS_CODESIGN_IDENTITY:?Set MACOS_CODESIGN_IDENTITY to your Developer ID Application identity}"
SODIUM_LIB_DIR="${SODIUM_LIB_DIR:-/tmp/libsodium-static/src/libsodium/.libs}"

if [ ! -f "$SODIUM_LIB_DIR/libsodium.a" ]; then
  echo "Building static libsodium 1.0.18 in /tmp/libsodium-static ..."
  rm -rf /tmp/libsodium-static
  mkdir -p /tmp/libsodium-static && cd /tmp/libsodium-static
  curl -L "https://github.com/jedisct1/libsodium/releases/download/1.0.18-RELEASE/libsodium-1.0.18.tar.gz" -o libsodium-1.0.18.tar.gz
  tar xzf libsodium-1.0.18.tar.gz
  cd libsodium-1.0.18
  ./configure --disable-shared --enable-static
  make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  SODIUM_LIB_DIR="/tmp/libsodium-static/libsodium-1.0.18/src/libsodium/.libs"
fi

export VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"
export SODIUM_LIB_DIR
unset CARGO_TARGET_DIR SODIUM_USE_PKG_CONFIG
export PATH="$ROOT/.build-tools/bin:$HOME/.cargo/bin:$PATH"

cd "$ROOT"
MACOSX_DEPLOYMENT_TARGET=10.14 cargo build --locked --features hwcodec,flutter,unix-file-copy-paste --release
cp target/release/liblibrustdesk.dylib target/release/librustdesk.dylib

cd flutter
MAC_ARCH="$(uname -m | sed 's/arm64/arm64/;s/x86_64/x86_64/')"
FLUTTER_XCODE_ARCHS="$MAC_ARCH" FLUTTER_XCODE_ONLY_ACTIVE_ARCH=YES \
  "${FLUTTER_ROOT:-$ROOT/.build-tools/flutter-3.24.5}/bin/flutter" build macos --release
cd "$ROOT"

# Sign all Mach-O components with the same Developer ID + hardened runtime.
find "$APP/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "FlutterMacOS" -o -name "App" \) | while read -r bin; do
  codesign --force --options runtime -s "$IDENTITY" "$bin"
done
find "$APP/Contents/Frameworks" -name "*.framework" -type d | while read -r fw; do
  codesign --force --options runtime -s "$IDENTITY" "$fw"
done
codesign --force --options runtime -s "$IDENTITY" "$APP/Contents/MacOS/${APP_NAME}"
codesign --force --options runtime -s "$IDENTITY" "$APP"

STAGE="$ROOT/.dmg-stage"
DMG="$ROOT/dal-seen-${VERSION}-$(uname -m).dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "${APP_NAME} Installer" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "Created $DMG"
