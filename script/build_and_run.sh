#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="BackgroundComputerUse"
BUNDLE_ID="xyz.dubdub.backgroundcomputeruse"
MIN_SYSTEM_VERSION="14.0"
DEV_KEYCHAIN="${BACKGROUND_COMPUTER_USE_DEV_KEYCHAIN:-$HOME/Library/Keychains/background-computer-use-dev.keychain-db}"
USE_DEV_KEYCHAIN=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALL_DIR="${BACKGROUND_COMPUTER_USE_INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
CORE_XPC_NAME="BackgroundComputerUseCoreXPCService"
CORE_XPC_ID="xyz.dubdub.backgroundcomputeruse.CoreXPC"
CORE_XPC_BUNDLE="$APP_CONTENTS/XPCServices/$CORE_XPC_NAME.xpc"
CORE_XPC_CONTENTS="$CORE_XPC_BUNDLE/Contents"
CORE_XPC_MACOS="$CORE_XPC_CONTENTS/MacOS"
CORE_XPC_BINARY="$CORE_XPC_MACOS/$CORE_XPC_NAME"
CORE_XPC_INFO_PLIST="$CORE_XPC_CONTENTS/Info.plist"

if [ -z "${BACKGROUND_COMPUTER_USE_SIGNING_IDENTITY:-}" ] && [ ! -f "$DEV_KEYCHAIN" ]; then
  "$ROOT_DIR/script/bootstrap_signing_identity.sh"
fi

if [ -n "${BACKGROUND_COMPUTER_USE_SIGNING_IDENTITY:-}" ]; then
  SIGNING_IDENTITY="$BACKGROUND_COMPUTER_USE_SIGNING_IDENTITY"
else
  SIGNING_IDENTITY=""

  if [ -d "$APP_BUNDLE" ]; then
    PREFERRED_CERT_SHA1=$(codesign -d -r- "$APP_BUNDLE" 2>&1 | sed -n 's/.*certificate root = H"\([[:xdigit:]]*\)".*/\1/p' | head -1)
    if [ -n "$PREFERRED_CERT_SHA1" ] && [ -f "$DEV_KEYCHAIN" ]; then
      MATCHING_IDENTITY=$(security find-identity -v -p codesigning "$DEV_KEYCHAIN" 2>/dev/null | awk -v target="$PREFERRED_CERT_SHA1" '$2 == target { print $2; exit }')
      if [ -n "$MATCHING_IDENTITY" ]; then
        SIGNING_IDENTITY="$MATCHING_IDENTITY"
        USE_DEV_KEYCHAIN=1
      fi
    fi
  fi

  if [ -z "$SIGNING_IDENTITY" ] && [ -f "$DEV_KEYCHAIN" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning "$DEV_KEYCHAIN" 2>/dev/null | awk 'NR==1 {print $2}')
    if [ -n "$SIGNING_IDENTITY" ]; then
      USE_DEV_KEYCHAIN=1
    fi
  fi

  if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk 'NR==1 {print $2}')
  fi

  if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="-"
  fi
fi

cd "$ROOT_DIR"

if [ "$MODE" != "build" ]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

if [ "${BACKGROUND_COMPUTER_USE_RELEASE_BUILD:-0}" = "1" ]; then
  ARM64_SCRATCH="$ROOT_DIR/.build/release-arm64"
  X86_64_SCRATCH="$ROOT_DIR/.build/release-x86_64"
  UNIVERSAL_DIR="$DIST_DIR/.universal-build"
  swift build --configuration release --arch arm64 --scratch-path "$ARM64_SCRATCH" --product "$APP_NAME"
  swift build --configuration release --arch arm64 --scratch-path "$ARM64_SCRATCH" --product "$CORE_XPC_NAME"
  swift build --configuration release --arch x86_64 --scratch-path "$X86_64_SCRATCH" --product "$APP_NAME"
  swift build --configuration release --arch x86_64 --scratch-path "$X86_64_SCRATCH" --product "$CORE_XPC_NAME"
  mkdir -p "$UNIVERSAL_DIR"
  /usr/bin/lipo -create \
    "$(swift build --configuration release --arch arm64 --scratch-path "$ARM64_SCRATCH" --show-bin-path)/$APP_NAME" \
    "$(swift build --configuration release --arch x86_64 --scratch-path "$X86_64_SCRATCH" --show-bin-path)/$APP_NAME" \
    -output "$UNIVERSAL_DIR/$APP_NAME"
  /usr/bin/lipo -create \
    "$(swift build --configuration release --arch arm64 --scratch-path "$ARM64_SCRATCH" --show-bin-path)/$CORE_XPC_NAME" \
    "$(swift build --configuration release --arch x86_64 --scratch-path "$X86_64_SCRATCH" --show-bin-path)/$CORE_XPC_NAME" \
    -output "$UNIVERSAL_DIR/$CORE_XPC_NAME"
  BUILD_BINARY="$UNIVERSAL_DIR/$APP_NAME"
  CORE_XPC_BUILD_BINARY="$UNIVERSAL_DIR/$CORE_XPC_NAME"
else
  swift build --product "$APP_NAME"
  swift build --product "$CORE_XPC_NAME"
  BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
  CORE_XPC_BUILD_BINARY="$(swift build --show-bin-path)/$CORE_XPC_NAME"
fi

mkdir -p "$APP_BUNDLE"
rm -rf "$APP_CONTENTS"
mkdir -p "$APP_MACOS"
mkdir -p "$CORE_XPC_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$CORE_XPC_BUILD_BINARY" "$CORE_XPC_BINARY"
chmod +x "$APP_BINARY"
chmod +x "$CORE_XPC_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

cat >"$CORE_XPC_INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$CORE_XPC_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$CORE_XPC_ID</string>
  <key>CFBundleName</key>
  <string>$CORE_XPC_NAME</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>XPCService</key>
  <dict>
    <key>ServiceType</key>
    <string>Application</string>
  </dict>
</dict>
</plist>
PLIST

if [ "$USE_DEV_KEYCHAIN" -eq 1 ]; then
  security unlock-keychain -p "${BACKGROUND_COMPUTER_USE_DEV_KEYCHAIN_PASSWORD:-}" "$DEV_KEYCHAIN"
fi

if [ "$USE_DEV_KEYCHAIN" -eq 1 ]; then
  /usr/bin/codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --identifier "$CORE_XPC_ID" \
    --timestamp=none \
    --keychain "$DEV_KEYCHAIN" \
    "$CORE_XPC_BUNDLE"
  /usr/bin/codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --timestamp=none \
    --keychain "$DEV_KEYCHAIN" \
    "$APP_BUNDLE"
else
  /usr/bin/codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --identifier "$CORE_XPC_ID" \
    --timestamp=none \
    "$CORE_XPC_BUNDLE"
  /usr/bin/codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --timestamp=none \
    "$APP_BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALLED_APP_BUNDLE"
  cp -R "$APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
  /usr/bin/open "$INSTALLED_APP_BUNDLE"
}

case "$MODE" in
  build)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [build|run|--debug|--verify]" >&2
    exit 2
    ;;
esac
