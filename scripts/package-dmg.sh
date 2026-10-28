#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_IDENTITY="${1:-${SIGNING_IDENTITY:-}}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This script requires macOS.\n' >&2
  exit 1
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  cat >&2 <<'EOF'
Usage:
  SIGNING_IDENTITY="Sonic Route Distribution" scripts/package-dmg.sh
  scripts/package-dmg.sh "Sonic Route Distribution"

Create a self-signed Code Signing identity in Keychain Access first.
EOF
  exit 2
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  printf 'xcodebuild was not found. Install Xcode or set DEVELOPER_DIR.\n' >&2
  exit 1
fi

identities="$(security find-identity -p codesigning 2>&1 || true)"
if ! printf '%s\n' "$identities" | grep -Fq -- "\"$SIGNING_IDENTITY\""; then
  printf 'Code-signing identity not found in the Keychain: %s\n\n' "$SIGNING_IDENTITY" >&2
  printf '%s\n' "$identities" >&2
  exit 1
fi

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/DerivedData/SonicRoute-DMG}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
PROJECT_PATH="$ROOT_DIR/SonicRoute.xcodeproj"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/SonicRoute.app"
FRAMEWORK_PATH="$APP_PATH/Contents/Frameworks/SonicRouteCore.framework"
BUNDLE_IDENTIFIER="com.sonicroute.SonicRoute"
CORE_BUNDLE_IDENTIFIER="com.sonicroute.SonicRouteCore"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme SonicRoute \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  printf 'Build completed without producing %s\n' "$APP_PATH" >&2
  exit 1
fi

if [[ ! -d "$FRAMEWORK_PATH" ]]; then
  printf 'Embedded framework not found: %s\n' "$FRAMEWORK_PATH" >&2
  exit 1
fi

codesign --force --sign "$SIGNING_IDENTITY" \
  --identifier "$CORE_BUNDLE_IDENTIFIER" --timestamp=none "$FRAMEWORK_PATH"
codesign --force --sign "$SIGNING_IDENTITY" \
  --identifier "$BUNDLE_IDENTIFIER" --timestamp=none "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
mkdir -p "$DIST_DIR"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/sonic-route-dmg.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

ditto --rsrc --extattr --acl "$APP_PATH" "$temporary_directory/Sonic Route.app"
ln -s /Applications "$temporary_directory/Applications"

DMG_PATH="$DIST_DIR/SonicRoute-$version.dmg"
if [[ -e "$DMG_PATH" ]]; then
  printf 'Refusing to overwrite existing package: %s\n' "$DMG_PATH" >&2
  exit 1
fi

hdiutil create \
  -volname "Sonic Route" \
  -srcfolder "$temporary_directory" \
  -format UDZO \
  "$DMG_PATH"

codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

printf '\nCreated signed DMG: %s\n' "$DMG_PATH"
printf 'Signing identity: %s\n' "$SIGNING_IDENTITY"
printf 'This self-signed build is not notarized and may require manual Gatekeeper approval.\n'
