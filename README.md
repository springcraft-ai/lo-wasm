# lo-wasm

Build recipe for [LibreOffice](https://www.libreoffice.org/) compiled to WebAssembly with Qt 5, intended for embedding via the [zetajs](https://github.com/allotropia/zetajs) JavaScript bridge.

Each tagged release publishes a single `lo-wasm-${tag}.tar.gz` containing:

- The WebAssembly bundle: `soffice.{js,wasm,data,data.js,data.js.metadata}`
- `LICENSES/` — license texts for every component in the bundle
- `manifest.json` — the SHA-256 of every file in the tarball plus the upstream commit hashes used to produce it

## Build inputs

| Component | Repository | Branch |
|---|---|---|
| LibreOffice core | `git.libreoffice.org/core` | `distro/allotropia/zeta-24-2` |
| Emscripten | `github.com/allotropia/emscripten` | `fixed-3.1.65` |
| Qt 5 | `github.com/allotropia/qt5` | `5.15.2+wasm` |

`versions.json` pins a specific SHA for each component at every tag. The build does not float pins.

## Build flags

The LibreOffice configure invocation uses the `LibreOfficeWASM32` distro configuration plus the following slimming flags:

```
--without-fonts
--without-help
--with-locales=en
--disable-extensions
--disable-lotuswordpro
```

These assume the embedding environment supplies fonts at runtime and never exposes LibreOffice's user interface. They are not appropriate for builds intended to expose the full UI.

## Building

Local (requires Docker on a Linux host or a Linux VM):

```
./build.sh
```

Tagged release: pushing a `v*` tag invokes `.github/workflows/build.yml` on `ubuntu-latest`, which runs the same `build.sh` and creates a GitHub Release with `lo-wasm-${tag}.tar.gz` and `manifest.json` attached.

## License

The build recipe in this repository — Dockerfile, scripts, workflow files — is licensed under the Apache License, Version 2.0. See `LICENSE`.

The Apache-2.0 license does not apply to the binary artifacts produced by the recipe. Each component is governed by its upstream license, reproduced in `LICENSES/` of every release tarball:

| Component | License |
|---|---|
| LibreOffice | Mozilla Public License 2.0, with components under LGPL-3.0+ and GPL-3.0 |
| Qt 5 | GNU Lesser General Public License 3.0 |
| Emscripten | MIT License and University of Illinois/NCSA Open Source License |

A recipient of a release tarball receives the binary under the union of those terms.

This repository at the relevant release tag is the corresponding-source reference for the published binaries: the upstream commits used are recorded in `versions.json`, and rebuilding at that tag fetches them. Downstream redistributors of the binaries can point recipients here to satisfy MPL-2.0 §3 and LGPL-3.0 §4.

## Trademarks

"LibreOffice" and "The Document Foundation" are trademarks of The Document Foundation. "Qt" is a trademark of The Qt Company Ltd. This repository is not affiliated with, endorsed by, or sponsored by either entity.
