# Open Everything for macOS

A native macOS file viewer built with SwiftUI, AppKit, Quick Look, and Uniform Type Identifiers. It does not run in a browser.

It includes a custom icon displayed in Finder, the Dock, and Launchpad.

Open Everything is free software released under the GNU General Public License
version 3. Source code and releases are available at
https://github.com/mhartwellyen-droid/open-everything-macos.

## What it opens

- NES ROMs run directly in the bundled emulator, with video, audio, and keyboard controls.
- 3D models open in an interactive native viewer with orbit, pan, and zoom controls. Supported formats include OBJ, STL, PLY, DAE, 3DS, Alembic, SceneKit, and USD/USDZ variants.
- Any format supported by macOS Quick Look, including common images, PDFs, audio, video, Office/iWork documents, fonts, 3D assets, and many archives.
- ZIP, 7Z, RAR, TAR, GZIP, BZIP2, and XZ-family archives open in a native content browser with safe-path validation and Extract All to a chosen folder.
- Text and source-code files in a selectable raw-text view.
- Unknown, proprietary, or partially corrupted files in a hexadecimal inspector.
- Any file in its default installed Mac application.
- Windows and Linux guests run through the built-in Apple Virtualization framework without a third-party VM application.
- Windows installers, scripts, shortcuts, and DOS-style programs are routed appropriately for `.msi`, `.bat`, `.cmd`, `.com`, and `.lnk` files.
- Any selected file can be exported as a standalone macOS `.app` wrapper with the file copied inside.
- Trash icons remove entries only from Open Everything’s Recent list and never delete or move the Finder file.
- Apple Silicon users see Rosetta 2 status plus a copyable installation command before launching Windows files.
- Windows `.iso` and `.img` files can be used as installation media for the built-in Windows VM.
- Linux `.sh` scripts can run through the macOS shell after a safety confirmation; `.deb` and `.rpm` packages are identified with clear Linux-runtime guidance.
- Legacy `.app` bundles show accurate guidance for 32-bit Mac applications, which require macOS Mojave or earlier and cannot be restored by Rosetta 2.
- The Compatibility Center reports Mac architecture, Rosetta 2, and native VM readiness.
- The built-in VM creates persistent Linux or Windows guests from user-supplied, architecture-compatible ISO or IMG files.
- Removing the bundled Wine runtime reduces the installer by hundreds of megabytes; guest operating systems are installed on demand.
- EXE, MSI, BAT, CMD, COM, and LNK files can install a Wine runtime on first use and run directly without a Windows ISO; the app installer remains lightweight.
- The Compatibility Center includes an ISO tutorial and official Windows and Ubuntu download links for users who want a full VM.
- The VM screen explains that it unlocks complete guest desktops, Windows software beyond Wine, Linux packages and ELF programs, persistent storage, networking, and isolated testing.
- The Updates screen opens the latest Open Everything release from inside the app.
- Releases are Developer ID signed and notarized so Gatekeeper can open them normally; first-launch help and the DMG README keep the narrowly scoped `sudo xattr` command only as fallback troubleshooting.
- Toolbar actions have descriptive labels and help text, Windows files always route through Wine instead of macOS Launch Services, and generated app wrappers contain a dedicated native launcher that runs their embedded Windows file without reopening Open Everything.
- The standalone launcher owns an explicit AppKit event loop and displays a preparation window immediately, preventing silent startup exits.

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

Before publishing a release, complete the physical Apple Silicon EXE launch
check in [`APPLE-SILICON-EXE-RELEASE-CHECK.md`](APPLE-SILICON-EXE-RELEASE-CHECK.md).
The build validates bundle structure and signatures, while the checklist verifies
the Rosetta, Wine installation, and real EXE launch flows that CI cannot emulate.

## Privacy

Files stay on your Mac. The app has no network code, analytics, uploads, or accounts.