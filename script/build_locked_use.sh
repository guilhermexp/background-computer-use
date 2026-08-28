#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_DIR/.build/locked-use"
BUNDLE_DIR="$REPO_DIR/dist/BCUAuthorizationPlugin.bundle"
BROKER_PATH="$REPO_DIR/dist/BackgroundComputerUseLockedBrokerService"
SIGN_IDENTITY="${BACKGROUND_COMPUTER_USE_SIGN_IDENTITY:--}"

cd "$REPO_DIR"
swift build -c release --product BCUAuthorizationPluginBundle
swift build -c release --product BackgroundComputerUseLockedBrokerService
LIBRARY_PATH="$(swift build -c release --show-bin-path)/libBCUAuthorizationPluginBundle.dylib"
BUILT_BROKER_PATH="$(swift build -c release --show-bin-path)/BackgroundComputerUseLockedBrokerService"
test -f "$LIBRARY_PATH"
test -f "$BUILT_BROKER_PATH"

mkdir -p "$BUILD_DIR" "$BUNDLE_DIR/Contents/MacOS"
cp "$LIBRARY_PATH" "$BUNDLE_DIR/Contents/MacOS/BCUAuthorizationPlugin"
cp "$BUILT_BROKER_PATH" "$BROKER_PATH"
plutil -create xml1 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string xyz.dubdub.backgroundcomputeruse.AuthorizationPlugin "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleName -string BCUAuthorizationPlugin "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleExecutable -string BCUAuthorizationPlugin "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundlePackageType -string BNDL "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleVersion -string 1 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.0.0 "$BUNDLE_DIR/Contents/Info.plist"
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$BUNDLE_DIR"
codesign --force --timestamp=none --options runtime --sign "$SIGN_IDENTITY" "$BROKER_PATH"
codesign --verify --deep --strict "$BUNDLE_DIR"
codesign --verify --strict "$BROKER_PATH"
nm -gU "$BUNDLE_DIR/Contents/MacOS/BCUAuthorizationPlugin" | grep '_AuthorizationPluginCreate'
echo "bundle=$BUNDLE_DIR"
echo "broker=$BROKER_PATH"
