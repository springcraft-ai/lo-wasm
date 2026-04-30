# lo-wasm

Build recipe for the LibreOffice WebAssembly bundle consumed by Springcraft's [Ink](https://get-ink.app) desktop app.

This repository's outputs let Ink convert `.docx` templates to PDF entirely client-side, with no runtime CDN dependency. It exists so we can ship the WASM bundle inside a signed installer rather than fetching ~80 MB from `cdn.zetaoffice.net` on first launch.

It is also the **public source pointer** for the LGPL-3.0 §4 substitution requirement: anyone who receives an Ink installer can replace the bundled WebAssembly with their own build by pointing it at a directory of replacement binaries (see `INK_LO_URL` in the Ink Acknowledgments panel).

## What this repo produces

A single GitHub Release per tag containing:

```
lo-wasm-${tag}.tar.gz
├── soffice.js                     Emscripten loader
├── soffice.wasm                   compiled WebAssembly binary
├── soffice.data                   preloaded VFS (fonts, configs, registry)
├── soffice.data.js.metadata       VFS manifest (separate-metadata build)
├── soffice.data.js                VFS shim
└── LICENSES/
    ├── LibreOffice.txt
    ├── Qt5.txt
    └── Emscripten.txt
manifest.json                       sha256 + size of every file in the tarball
```

The whole tarball is roughly **80 MB**.

## How to consume from Ink

Ink's monorepo pins this repo's release tag in `client/ink/lo-wasm.lock.json`:

```json
{ "tag": "v...", "sha256": "..." }
```

`client/ink/scripts/fetch-lo-wasm.mjs` reads the lockfile, downloads the tagged release tarball, verifies the sha256, and extracts into `client/ink/resources/lo-wasm/`. From there `electron-builder` packs it into the signed `.app` / `.exe` via the `extraResources` configuration. At runtime the renderer iframe loads `soffice.js` from `file://` — no network involved.

## How a build works

1. `versions.json` pins the source commits for LibreOffice (`distro/allotropia/zeta-24-2` branch on git.libreoffice.org/core), Emscripten (`fixed-3.1.65` branch on allotropia/emscripten), and Qt 5 (`5.15.2+wasm` branch on allotropia/qt5).
2. The multi-stage `Dockerfile` clones each component at its pinned commit, builds emsdk → Qt 5 (qtbase only) → LibreOffice (Qt-backed WASM build), and stages the contents of `workdir/installation/LibreOffice/emscripten/` plus license texts into `/dist/`.
3. `build.sh` invokes the Dockerfile, copies `/dist/` out, and runs `gen-manifest.mjs` to produce `manifest.json`.
4. The GitHub Actions workflow (`.github/workflows/build.yml`) runs the same flow on a tag push, packages the output, and creates a GitHub Release.

Build host requirements: `ubuntu-latest` GHA runner is sufficient (~1 h end-to-end). Local builds work on any Linux box with Docker; macOS via Docker Desktop also works but is slower.

## Pinning policy

ZetaJS (the JS wrapper Ink uses) tracks the *branch tip* of `distro/allotropia/zeta-24-2`, not specific commits, and the public `cdn.zetaoffice.net/zetaoffice_latest/` is rebuilt off whatever's currently on that branch. There is no published compatibility matrix between zetajs npm versions and LO commits.

Our policy:

- Pin `loCore`, `emsdk`, `qt5` in `versions.json` to the **branch tip captured at the moment of each build**.
- Capture the rationale (date, what zetajs npm version we're pairing with).
- Smoke-test against a known-good `.docx` template post-build.
- **Never rebuild without bumping the pin.** Rebuilding the same `versions.json` on a different day would silently re-roll the dice on ABI compatibility.
- Bump only when we bump the zetajs npm pin in Ink, or when there's a security/correctness reason to refresh.

## Licenses

This repository (Dockerfile, build scripts, workflow, README) is licensed under **Apache-2.0** — see `LICENSE`. It is Springcraft-authored build tooling, not a derived work of LibreOffice.

The **outputs** carry their upstream component licenses, packed into each release tarball under `LICENSES/`:

| Component | License |
|---|---|
| LibreOffice | MPL-2.0 + LGPL-3.0+ + GPL-3.0 (in places) |
| Qt 5 | LGPL-3.0 |
| Emscripten | MIT + University of Illinois/NCSA |

Source pointers for the binaries inherit from upstream. The exact commits are recorded in `manifest.json` for every release. For LibreOffice that's `git.libreoffice.org/core` at the commit listed in `versions.json#loCore`; for Qt 5 that's `github.com/allotropia/qt5` at `versions.json#qt5`; for Emscripten that's `github.com/allotropia/emscripten` at `versions.json#emsdk`.

## Trademarks

"LibreOffice" and "The Document Foundation" are trademarks of The Document Foundation. "Qt" is a trademark of The Qt Company Ltd. This repository is not affiliated with or endorsed by either; it builds their software under the terms of the licenses above.
