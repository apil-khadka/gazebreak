# GazeBreak 0.1.0

The first public release of GazeBreak, a quiet macOS menu-bar companion for regular screen breaks.

## Included

- 20-minute focus timer with configurable 30-second distance breaks
- 15-minute longer reset after roughly two hours of accumulated focus time
- Pause, resume, reset, skip, and reminder enable/disable controls
- Automatic pause around inactive macOS sessions and display sleep
- Settings persistence between launches
- Apple Silicon macOS app bundle with an abstract GazeBreak logo

## Compatibility

- macOS 13 or later
- Apple Silicon (arm64)

GazeBreak is a reminder tool, not medical advice or a treatment for eye conditions.

## Production release policy

The `v0.1.0` artifact is a legacy arm64 build with ad-hoc signing and no Apple notarization. It is not suitable for Homebrew distribution.

Version-tagged production releases use `GazeBreak-macOS-universal.zip`, containing a universal `arm64` + `x86_64` app for macOS 13 or later. The release workflow signs the app with a Developer ID Application certificate, submits it to Apple with `xcrun notarytool`, staples the ticket, and verifies it with `codesign`, `spctl`, and `xcrun stapler` before publishing the ZIP and its SHA-256 checksum.
