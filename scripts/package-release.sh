#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/GazeBreak.app"
ICONSET_DIR="$DIST_DIR/GazeBreak.iconset"

cd "$ROOT_DIR"
swift build -c release -Xswiftc -warnings-as-errors

rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICONSET_DIR"

SOURCE_ICON="$ROOT_DIR/Sources/GazeBreak/Resources/GazeBreakLogo.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE_ICON" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE_ICON" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/GazeBreakLogo.icns"
cp "$BUILD_DIR/GazeBreak" "$APP_DIR/Contents/MacOS/GazeBreak"
cp "$SOURCE_ICON" "$APP_DIR/Contents/Resources/GazeBreakLogo.png"
cp "$ROOT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIST_DIR/GazeBreak-macOS-arm64.zip"

echo "Packaged: $DIST_DIR/GazeBreak-macOS-arm64.zip"
