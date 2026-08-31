#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/.build/release-architectures}"
APP_DIR="$DIST_DIR/GazeBreak.app"
ICONSET_DIR="$DIST_DIR/GazeBreak.iconset"
ZIP_NAME="${ZIP_NAME:-GazeBreak-macOS-universal.zip}"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
APP_VERSION="${APP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/App/Info.plist")}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-}"
REQUIRE_SIGNING="${REQUIRE_SIGNING:-0}"
CREATE_ZIP="${CREATE_ZIP:-1}"

die() {
    print -u2 "error: $*"
    exit 1
}

if [[ ! "$APP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    die "APP_VERSION must be a semantic version, got '$APP_VERSION'"
fi

if [[ "$REQUIRE_SIGNING" == "1" && "$SIGNING_IDENTITY" == "-" ]]; then
    die "a Developer ID Application identity is required when REQUIRE_SIGNING=1"
fi

cd "$ROOT_DIR"
rm -rf "$DIST_DIR" "$BUILD_ROOT"
mkdir -p "$DIST_DIR" "$BUILD_ROOT" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICONSET_DIR"

build_architecture() {
    local arch="$1"
    local triple="${arch}-apple-macosx13.0"
    local scratch_path="$BUILD_ROOT/$arch"
    local output_path="$scratch_path/${arch}-apple-macosx/release/GazeBreak"

    swift build \
        -c release \
        --triple "$triple" \
        --scratch-path "$scratch_path" \
        -Xswiftc -warnings-as-errors

    [[ -f "$output_path" ]] || die "SwiftPM did not produce $output_path"
    cp "$output_path" "$BUILD_ROOT/GazeBreak-$arch"
}

build_architecture arm64
build_architecture x86_64

lipo -create \
    "$BUILD_ROOT/GazeBreak-arm64" \
    "$BUILD_ROOT/GazeBreak-x86_64" \
    -output "$APP_DIR/Contents/MacOS/GazeBreak"

lipo -info "$APP_DIR/Contents/MacOS/GazeBreak" | grep -q 'arm64' \
    || die "universal binary is missing arm64"
lipo -info "$APP_DIR/Contents/MacOS/GazeBreak" | grep -q 'x86_64' \
    || die "universal binary is missing x86_64"

SOURCE_ICON="$ROOT_DIR/Sources/GazeBreak/Resources/GazeBreakLogo.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE_ICON" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE_ICON" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/GazeBreakLogo.icns"
cp "$SOURCE_ICON" "$APP_DIR/Contents/Resources/GazeBreakLogo.png"
cp "$ROOT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE.txt"
cp "$ROOT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$APP_VERSION" "$APP_DIR/Contents/Info.plist"

codesign_args=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign_args+=(--options runtime --timestamp)
fi
if [[ -n "$KEYCHAIN_PATH" ]]; then
    codesign_args+=(--keychain "$KEYCHAIN_PATH")
fi

codesign "${codesign_args[@]}" "$APP_DIR/Contents/MacOS/GazeBreak" >/dev/null
codesign "${codesign_args[@]}" "$APP_DIR" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [[ "$CREATE_ZIP" == "1" ]]; then
    (cd "$DIST_DIR" && /usr/bin/zip -qry "$ZIP_NAME" GazeBreak.app -x '*/.DS_Store' '__MACOSX/*')
    if ! unzip -Z1 "$ZIP_PATH" | awk '/^__MACOSX\// {bad=1} END {exit bad}'; then
        die "release ZIP contains __MACOSX"
    fi
    if ! unzip -Z1 "$ZIP_PATH" | awk '!/^GazeBreak\.app(\/|$)/ {bad=1} END {exit bad}'; then
        die "release ZIP contains files outside GazeBreak.app"
    fi
    print "Packaged: $ZIP_PATH"
fi

print "Universal binary: $APP_DIR/Contents/MacOS/GazeBreak"
print "Signing identity: $SIGNING_IDENTITY"
