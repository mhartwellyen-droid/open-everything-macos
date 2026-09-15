# Open Everything for macOS

A native macOS file viewer built with SwiftUI, AppKit, Quick Look, and Uniform Type Identifiers. It does not run in a browser.

## What it opens

- NES ROMs run directly in the bundled emulator, with video, audio, and keyboard controls.
- Any format supported by macOS Quick Look, including common images, PDFs, audio, video, Office/iWork documents, fonts, 3D assets, and many archives.
- Text and source-code files in a selectable raw-text view.
- Unknown, proprietary, or partially corrupted files in a hexadecimal inspector.
- Any file in its default installed Mac application.
- Windows executables can be handed to Whisky, CrossOver, or Wine when one is installed.

### NES controls

- D-pad: arrow keys
- A: `Z`
- B: `X`
- Start: Return
- Select: Shift

No program can fully decode every file format ever created. Encrypted files require their password, and proprietary formats may require the application that created them. Open Everything still exposes metadata and raw bytes when no visual decoder is installed.

## Build on a Mac

Requirements: macOS 13 or later and Xcode 15 or later.

1. Open `Package.swift` in Xcode.
2. Select **My Mac** as the run destination.
3. Press **Run**.
4. To export a standalone app, choose **Product → Archive**, then **Distribute App → Copy App**.

You can also run it from Terminal:

```sh
cd mac-universal-opener
swift run OpenEverything
```

To create a standalone app you can drag into Applications:

```sh
cd mac-universal-opener
sh build-app.sh
```

The finished app will be at `dist/OpenEverything.app`.

To create an installable DMG:

```sh
cd mac-universal-opener
sh make-dmg.sh
```

The finished installer will be at `OpenEverything-1.0.0.dmg`. Open it, then
drag **Open Everything** into **Applications**.

## Privacy

Files stay on your Mac. The app has no network code, analytics, uploads, or accounts.