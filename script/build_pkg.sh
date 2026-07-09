#!/usr/bin/env bash
set -euo pipefail

# Build a signed macOS installer package (.pkg) for Jamf Preload Manager.
#
# What it does:
#   1. Builds the app in release configuration (Swift Package Manager).
#   2. Assembles a .app bundle (icon + Info.plist) in a temporary staging area.
#   3. Codesigns the .app with your Developer ID Application identity (hardened runtime).
#   4. Produces a signed installer .pkg with your Developer ID Installer identity.
#   5. (Optional) Notarizes and staples the .pkg.
#
# The finished installer is written to the repository root as "<DisplayName>.pkg".
#
# Usage:
#   ./script/build_pkg.sh                 # build + sign the pkg
#   ./script/build_pkg.sh --notarize      # build + sign + notarize + staple the pkg
#   ./script/build_pkg.sh --notarize --staple-app
#   ./script/build_pkg.sh --help
#
# Configuration (put in script/signing.env, or export before running):
#   APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   PKG_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)"
#   APP_ENTITLEMENTS="/absolute/path/to/entitlements.plist"   # optional
#   NOTARY_KEYCHAIN_PROFILE="AC_NOTARY"                        # required for --notarize
#   NOTARY_KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"  # optional
#
# See script/signing.env.example and docs/Notarization-HowTo.md for details.

APP_NAME="JamfPreloadManager"
DISPLAY_NAME="Jamf Preload Manager"
BUNDLE_NAME="${DISPLAY_NAME}.app"
BUNDLE_ID="io.github.woodmember.JamfPreloadManager"
APP_VERSION="0.8p"
APP_BUILD_VERSION="0.8"
MIN_SYSTEM_VERSION="14.0"

ENABLE_NOTARIZE="${ENABLE_NOTARIZE:-0}"
STAPLE_APP="${STAPLE_APP:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_CACHE_DIR="$ROOT_DIR/.build-cache"
CLANG_CACHE_DIR="$BUILD_CACHE_DIR/clang-module-cache"
SWIFTPM_CACHE_DIR="$BUILD_CACHE_DIR/swiftpm-cache"
BUILD_HOME="$BUILD_CACHE_DIR/home"
STAGE_DIR="$BUILD_CACHE_DIR/stage"
APP_BUNDLE="$STAGE_DIR/$BUNDLE_NAME"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="${APP_ICON_SOURCE:-$ROOT_DIR/Resources/AppIcon.png}"
APP_ICON_NAME="AppIcon"
APP_ICON_ICNS="$APP_RESOURCES/$APP_ICON_NAME.icns"

SIGNING_ENV_FILE="${SIGNING_ENV_FILE:-$SCRIPT_DIR/signing.env}"
if [[ -f "$SIGNING_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SIGNING_ENV_FILE"
fi

APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
PKG_SIGN_IDENTITY="${PKG_SIGN_IDENTITY:-}"
APP_ENTITLEMENTS="${APP_ENTITLEMENTS:-}"
PKG_NAME="${PKG_NAME:-${DISPLAY_NAME}.pkg}"
PKG_PATH="$ROOT_DIR/$PKG_NAME"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_KEYCHAIN_PATH="${NOTARY_KEYCHAIN_PATH:-}"

XCODE_SWIFT="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
XCODE_SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

usage() {
  sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case "$arg" in
    --notarize) ENABLE_NOTARIZE=1 ;;
    --staple-app) STAPLE_APP=1 ;;
    --no-notarize) ENABLE_NOTARIZE=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$CLANG_CACHE_DIR" "$SWIFTPM_CACHE_DIR" "$BUILD_HOME"

if [[ -x "$XCODE_SWIFT" ]]; then
  SWIFT_BIN="$XCODE_SWIFT"
else
  SWIFT_BIN="$(command -v swift)"
fi

BUILD_ENV=(
  "HOME=$BUILD_HOME"
  "CLANG_MODULE_CACHE_PATH=$CLANG_CACHE_DIR"
  "SWIFTPM_MODULECACHE_OVERRIDE=$CLANG_CACHE_DIR"
  "SWIFTPM_CUSTOM_CACHE_PATH=$SWIFTPM_CACHE_DIR"
)
if [[ -d "$XCODE_SDK" ]]; then
  BUILD_ENV+=("SDKROOT=$XCODE_SDK")
fi

echo "==> Building release binary"
env "${BUILD_ENV[@]}" "$SWIFT_BIN" build --package-path "$ROOT_DIR" -c release
BUILD_BINARY="$(env "${BUILD_ENV[@]}" "$SWIFT_BIN" build --package-path "$ROOT_DIR" -c release --show-bin-path)/$APP_NAME"

echo "==> Assembling app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$APP_ICON_SOURCE" ]]; then
  ICONSET_DIR="$BUILD_CACHE_DIR/$APP_ICON_NAME.iconset"
  rm -rf "$ICONSET_DIR"; mkdir -p "$ICONSET_DIR"
  /usr/bin/sips -z 16 16   "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png"      >/dev/null
  /usr/bin/sips -z 32 32   "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png"   >/dev/null
  /usr/bin/sips -z 32 32   "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png"      >/dev/null
  /usr/bin/sips -z 64 64   "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png"   >/dev/null
  /usr/bin/sips -z 128 128 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png"    >/dev/null
  /usr/bin/sips -z 256 256 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  /usr/bin/sips -z 256 256 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png"    >/dev/null
  /usr/bin/sips -z 512 512 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  /usr/bin/sips -z 512 512 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png"    >/dev/null
  cp "$APP_ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
  /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$APP_ICON_ICNS"
fi

ICON_PLIST_FRAGMENT=""
if [[ -f "$APP_ICON_ICNS" ]]; then
  ICON_PLIST_FRAGMENT="  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME</string>"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD_VERSION</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
$ICON_PLIST_FRAGMENT
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -z "$APP_SIGN_IDENTITY" ]]; then
  echo "error: APP_SIGN_IDENTITY is not set. Configure script/signing.env (see signing.env.example)." >&2
  exit 1
fi

echo "==> Signing app bundle with: $APP_SIGN_IDENTITY"
CODESIGN_ARGS=(--force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY")
if [[ -n "$APP_ENTITLEMENTS" ]]; then
  [[ -f "$APP_ENTITLEMENTS" ]] || { echo "error: APP_ENTITLEMENTS not found: $APP_ENTITLEMENTS" >&2; exit 1; }
  CODESIGN_ARGS+=(--entitlements "$APP_ENTITLEMENTS")
fi
/usr/bin/codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Building installer package"
rm -f "$PKG_PATH"
TMP_DIR="$(mktemp -d)"
STAGING_ROOT="$TMP_DIR/root"
COMPONENT_PLIST="$TMP_DIR/component.plist"
COMPONENT_PKG="$TMP_DIR/component.pkg"
mkdir -p "$STAGING_ROOT/Applications"
cp -R "$APP_BUNDLE" "$STAGING_ROOT/Applications/"

/usr/bin/pkgbuild --analyze --root "$STAGING_ROOT" "$COMPONENT_PLIST"
/usr/bin/plutil -replace 0.BundleIsRelocatable -bool NO "$COMPONENT_PLIST"
/usr/bin/pkgbuild --root "$STAGING_ROOT" --component-plist "$COMPONENT_PLIST" --install-location / "$COMPONENT_PKG"

PRODUCTBUILD_ARGS=(--package "$COMPONENT_PKG")
if [[ -n "$PKG_SIGN_IDENTITY" ]]; then
  echo "==> Signing installer with: $PKG_SIGN_IDENTITY"
  PRODUCTBUILD_ARGS+=(--sign "$PKG_SIGN_IDENTITY")
else
  echo "warning: PKG_SIGN_IDENTITY not set — creating an UNSIGNED installer." >&2
fi
PRODUCTBUILD_ARGS+=("$PKG_PATH")
/usr/bin/productbuild "${PRODUCTBUILD_ARGS[@]}"
rm -rf "$TMP_DIR"
echo "==> Created: $PKG_PATH"

if [[ "$ENABLE_NOTARIZE" == "1" ]]; then
  [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]] || { echo "error: --notarize requires NOTARY_KEYCHAIN_PROFILE." >&2; exit 1; }
  echo "==> Submitting for notarization (profile: $NOTARY_KEYCHAIN_PROFILE)"
  NOTARY_ARGS=(notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait)
  [[ -n "$NOTARY_KEYCHAIN_PATH" ]] && NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN_PATH")
  /usr/bin/xcrun "${NOTARY_ARGS[@]}"
  echo "==> Stapling and validating pkg"
  /usr/bin/xcrun stapler staple "$PKG_PATH"
  /usr/bin/xcrun stapler validate "$PKG_PATH"
  /usr/sbin/spctl -a -vv --type install "$PKG_PATH" || true
  if [[ "$STAPLE_APP" == "1" ]]; then
    echo "==> Stapling app bundle"
    /usr/bin/xcrun stapler staple "$APP_BUNDLE"
  fi
fi

echo
echo "Done. Installer: $PKG_PATH"
echo "Verify signature with: pkgutil --check-signature \"$PKG_PATH\""
