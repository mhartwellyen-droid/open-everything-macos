# Open Everything

A native macOS utility that previews supported files and safely inspects unknown formats as text, metadata, or hexadecimal bytes.

## Run & Operate

- `pnpm --filter @workspace/api-server run dev` — run the API server (port 5000)
- `pnpm run typecheck` — full typecheck across all packages
- `pnpm run build` — typecheck + build all packages
- `pnpm --filter @workspace/api-spec run codegen` — regenerate API hooks and Zod schemas from the OpenAPI spec
- `pnpm --filter @workspace/db run push` — push DB schema changes (dev only)
- Required env: `DATABASE_URL` — Postgres connection string

## Stack

- pnpm workspaces, Node.js 24, TypeScript 5.9
- API: Express 5
- DB: PostgreSQL + Drizzle ORM
- Validation: Zod (`zod/v4`), `drizzle-zod`
- API codegen: Orval (from OpenAPI spec)
- Build: esbuild (CJS bundle)

## Where things live

_Populate as you build — short repo map plus pointers to the source-of-truth file for DB schema, API contracts, theme files, etc._

## Architecture decisions

_Populate as you build — non-obvious choices a reader couldn't infer from the code (3-5 bullets)._

## Product

- Native SwiftUI macOS app; no website or cloud dependency.
- Opens files through a picker or drag-and-drop.
- Treats unsupported executable formats as compatibility targets, not merely preview targets.
- Runs iNES-format `.nes` ROMs in a bundled local emulator with keyboard controls and audio.
- Runs `.exe`, `.msi`, `.bat`, `.cmd`, `.com`, and `.lnk` directly through a Wine runtime downloaded on first use, so no Windows ISO is required and the DMG stays lightweight.
- Shows Apple Silicon users whether Rosetta 2 is present and provides a copyable installation command when it is missing.
- Uses Windows `.iso` and `.img` files as installation media for the built-in VM.
- Runs trusted `.sh` scripts through the macOS shell after confirmation and identifies `.deb`/`.rpm` packages as requiring Linux.
- Identifies legacy `.app` bundles and explains that 32-bit Mac software requires macOS Mojave or earlier; Rosetta 2 cannot translate it.
- Includes a Compatibility Center showing Mac architecture, Rosetta status, and native VM readiness.
- Runs persistent Linux and Windows guests through Apple’s built-in Virtualization framework without requiring a third-party VM app.
- Includes an ISO tutorial with official Windows and Ubuntu links plus a clear list of features unlocked by a full VM.
- Includes an Updates screen that opens the latest private GitHub release from inside the app.
- Trash buttons only remove items from the app’s Recent list; they never delete, move, or modify the Finder file.
- Shows first-launch Gatekeeper repair guidance in-app and includes a prominent README inside the DMG with the app-scoped `sudo xattr` command.
- The GitHub repository is public and the project is licensed under GPL-3.0.
- Windows toolbar actions share the same Wine runtime as the main Windows panel, and Apple Silicon checks Rosetta 2 before downloading or launching Wine.
- Generated Windows app wrappers contain a dedicated native launcher, selected payload, and icon. They run the payload directly through the shared Rosetta/Wine support without opening the Open Everything interface.
- The wrapper launcher explicitly owns its AppKit application lifecycle and displays a preparation window immediately; do not rely on an implicit SwiftPM app lifecycle.
- ZIP, 7Z, RAR, TAR, GZIP, BZIP2, and XZ-family files route to a native archive browser with traversal-path validation and Extract All to a user-selected folder.
- `mac-universal-opener/VERSION` is the single source for app metadata, DMG filenames, and release tags; tagged builds must match it.
- Uses a custom cyan-and-violet portal document icon in Finder, the Dock, and Launchpad; the macOS build generates its `.icns` variants from the source artwork.
- Can export any selected file as a macOS `.app` wrapper containing its own copy of the file.
- Moves selected files to Trash only after explicit confirmation.
- Opens common 3D formats in a native interactive SceneKit/ModelIO viewer, including OBJ, STL, PLY, DAE, 3DS, Alembic, SceneKit, and USD/USDZ variants.
- Uses macOS Quick Look for rich previews.
- Provides raw text, metadata, and capped hexadecimal inspection for unknown formats.
- Hands files to their default installed Mac application when needed.

## User preferences

_Populate as you build — explicit user instructions worth remembering across sessions._

## Gotchas

_Populate as you build — sharp edges, "always run X before Y" rules._

## Pointers

- See the `pnpm-workspace` skill for workspace structure, TypeScript setup, and package details
