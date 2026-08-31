# GazeBreak

A tiny macOS menu-bar app that helps prevent long, uninterrupted screen sessions.

![GazeBreak logo](Sources/GazeBreak/Resources/GazeBreakLogo.png)

GazeBreak is named for the small, intentional pause it creates in a long period of close-focus work. The abstract mark represents an opening and breathing room rather than a literal eye or medical symbol.

## Download

Download the latest Apple Silicon build from the [GitHub Releases page](https://github.com/apil-khadka/gazebreak/releases/latest). The release is distributed as `GazeBreak-macOS-arm64.zip`.

## Build a release locally

```bash
./scripts/package-release.sh
```

This creates `dist/GazeBreak.app` and `dist/GazeBreak-macOS-arm64.zip`.

## Run

1. Open the folder in Xcode.
2. Choose the `GazeBreak` executable scheme.
3. Run it on **My Mac**.

For a deterministic timer smoke test, run `swift run GazeBreak --self-test`. It exercises countdown advancement, the reminder boundary, and break completion without waiting 20 minutes.

The app is an accessory app, so it stays out of the Dock and lives in the menu bar. Click the eye and timer pill to pause, reset, change the interval, or change the break length.

The default timing is a 20-minute focus interval followed by a 30-second distance break. The reminder window is a floating panel that stays visible above other windows and across Spaces. Settings persist between launches, and the timer pauses when the macOS session becomes inactive.

After roughly two hours of accumulated focus time, the app shows a longer 15-minute reset. Short-break skips do not erase that accumulated focus time; the Reset button starts the two-hour cycle over.

The app does not diagnose or treat eye conditions. It is a reminder tool based on common digital-eye-strain guidance. If you have persistent symptoms or sudden flashes, a sudden increase in floaters, or a curtain/shadow in your vision, contact an eye-care professional promptly.
