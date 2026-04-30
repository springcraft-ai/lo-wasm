#!/usr/bin/env bash
# Wrapper around the Dockerfile. Reads pins from versions.json, builds
# the image, copies /dist out to ./dist, generates manifest.json, and
# (optionally) packages a release tarball.
#
# Usage:
#   ./build.sh                # build, output to ./dist/, no tarball
#   TAG=v0.0.1 ./build.sh     # also produce lo-wasm-v0.0.1.tar.gz
#
# Env:
#   DIST   override output directory (default: ./dist)
#   TAG    if set and not "untagged", also produce lo-wasm-${TAG}.tar.gz

set -euo pipefail

cd "$(dirname "$0")"

LO_COMMIT="$(node -p 'require("./versions.json").loCore')"
EMSDK_COMMIT="$(node -p 'require("./versions.json").emsdk')"
QT5_COMMIT="$(node -p 'require("./versions.json").qt5')"
LO_BRANCH="$(node -p 'require("./versions.json").loBranch')"
ZETAJS_NPM="$(node -p 'require("./versions.json").zetajsNpm')"

if [ "$LO_COMMIT" = "PENDING-FIRST-BUILD" ] \
   || [ "$EMSDK_COMMIT" = "PENDING-FIRST-BUILD" ] \
   || [ "$QT5_COMMIT" = "PENDING-FIRST-BUILD" ]; then
    cat >&2 <<EOF
ERROR: versions.json still has PENDING-FIRST-BUILD placeholders.
Resolve the branch tips and update versions.json before building.

Branches to snapshot (run "git ls-remote <repo> <branch>" to get the tip):
  loCore  ← $(node -p 'require("./versions.json").loBranch')   on git.libreoffice.org/core
  emsdk   ← $(node -p 'require("./versions.json").emsdkBranch')      on github.com/allotropia/emscripten
  qt5     ← $(node -p 'require("./versions.json").qt5Branch')         on github.com/allotropia/qt5

Then commit versions.json and run again.
EOF
    exit 1
fi

DIST="${DIST:-./dist}"
TAG="${TAG:-untagged}"

echo "==> Building lo-wasm with pins:"
echo "    LibreOffice (core): $LO_COMMIT  (branch $LO_BRANCH)"
echo "    Emscripten:         $EMSDK_COMMIT"
echo "    Qt 5:               $QT5_COMMIT"
echo "    zetajs npm pair:    $ZETAJS_NPM"
echo ""

docker build \
    --build-arg LO_COMMIT="$LO_COMMIT" \
    --build-arg EMSDK_COMMIT="$EMSDK_COMMIT" \
    --build-arg QT5_COMMIT="$QT5_COMMIT" \
    --target dist \
    -t lo-wasm-build:latest \
    .

mkdir -p "$DIST"
echo ""
echo "==> Extracting artifacts to $DIST"
CONTAINER="$(docker create lo-wasm-build:latest)"
trap 'docker rm "$CONTAINER" >/dev/null 2>&1 || true' EXIT
docker cp "$CONTAINER:/dist/." "$DIST/"

echo ""
echo "==> Generating manifest.json"
node ./gen-manifest.mjs "$DIST" > "$DIST/manifest.json"

if [ -n "${TAG:-}" ] && [ "$TAG" != "untagged" ]; then
    TARBALL="lo-wasm-${TAG}.tar.gz"
    echo ""
    echo "==> Creating $TARBALL"
    tar -czf "$TARBALL" -C "$DIST" .
    echo "==> Tarball SHA-256:"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$TARBALL"
    else
        shasum -a 256 "$TARBALL"
    fi
fi

echo ""
echo "==> Done. Output:"
ls -la "$DIST"
