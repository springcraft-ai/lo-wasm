# syntax=docker/dockerfile:1.7
#
# Multi-stage build for the LibreOffice WebAssembly bundle.
# All version pins arrive via --build-arg from build.sh — see README.md.
#
# Stages:
#   base        — Ubuntu 22.04 + build deps shared by every later stage
#   emsdk-stage — install pinned allotropia/emscripten via emsdk
#   qt-stage    — build Qt 5 (qtbase only) for wasm-emscripten
#   lo-stage    — build LibreOffice with --with-distro=LibreOfficeWASM32
#   dist        — minimal final stage staging just the artifacts
#
# Build artifacts land in the "dist" stage at /dist/.

ARG LO_COMMIT
ARG EMSDK_COMMIT
ARG QT5_COMMIT

# ----- base ---------------------------------------------------------------
FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

# Build dependencies. The set is taken from LibreOffice/core/static/README.wasm.md
# plus what's needed to build Qt5 + emscripten. Trim or extend during the
# first build pass — flag missing-dependency errors will surface fast.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential autoconf automake libtool pkg-config \
    python3 python3-pip flex bison nasm \
    ccache ninja-build cmake \
    perl libxml2-dev libxslt1-dev \
    zip unzip xz-utils ca-certificates \
    curl wget gperf zstd \
    && rm -rf /var/lib/apt/lists/*

# Use deterministic source paths so the bake of soffice.data doesn't leak
# the build host's directory layout into the WASM virtual filesystem.
WORKDIR /build

# ----- emsdk + emscripten (allotropia fork) -------------------------------
FROM base AS emsdk-stage
ARG EMSDK_COMMIT

# The allotropia emscripten fork is at github.com/allotropia/emscripten on
# branch fixed-3.1.65. emsdk is the version manager; we point it at the
# fork by replacing upstream/emscripten in its tree before activate.
RUN git clone https://github.com/emscripten-core/emsdk.git /opt/emsdk
WORKDIR /opt/emsdk

RUN ./emsdk install 3.1.65 && ./emsdk activate 3.1.65 \
    && rm -rf /opt/emsdk/upstream/emscripten \
    && git clone https://github.com/allotropia/emscripten.git /opt/emsdk/upstream/emscripten \
    && cd /opt/emsdk/upstream/emscripten \
    && git checkout "${EMSDK_COMMIT}" \
    && bash -c '. /opt/emsdk/emsdk_env.sh && ./bootstrap' \
    && cd /opt/emsdk \
    && ./emsdk activate 3.1.65

# Why bootstrap: replacing /opt/emsdk/upstream/emscripten with the
# allotropia fork drops the npm packages that `./emsdk install` would
# normally install in-place. Without bootstrap, em++ refuses to run
# with "emscripten setup is not complete (npm packages out-of-date)"
# and Qt5's configure trips on it.

ENV EMSDK=/opt/emsdk
ENV PATH="/opt/emsdk:/opt/emsdk/upstream/emscripten:/opt/emsdk/node/22.16.0_64bit/bin:${PATH}"

# Sanity check — the first build pass should print a recognisable
# emscripten version.
RUN bash -c "source /opt/emsdk/emsdk_env.sh && emcc --version | head -1"

# ----- Qt 5 (WASM-patched fork) -------------------------------------------
FROM emsdk-stage AS qt-stage
ARG QT5_COMMIT

WORKDIR /build/qt5
RUN git clone https://github.com/allotropia/qt5.git src
WORKDIR /build/qt5/src
RUN git checkout "${QT5_COMMIT}" \
    && ./init-repository --module-subset=qtbase

# Out-of-tree build for cleanliness.
WORKDIR /build/qt5/build
RUN bash -c 'source /opt/emsdk/emsdk_env.sh && /build/qt5/src/configure \
    -opensource -confirm-license \
    -xplatform wasm-emscripten \
    -feature-thread \
    -prefix /opt/qt5-wasm \
    QMAKE_CFLAGS+=-sSUPPORT_LONGJMP=wasm \
    QMAKE_CXXFLAGS+=-sSUPPORT_LONGJMP=wasm'

RUN bash -c 'source /opt/emsdk/emsdk_env.sh && \
    make -j"$(nproc)" module-qtbase && \
    make -j"$(nproc)" install'

# ----- LibreOffice (allotropia distro branch) -----------------------------
FROM qt-stage AS lo-stage
ARG LO_COMMIT
ARG LO_BRANCH=distro/allotropia/zeta-24-2

# LO refuses to build as root ("Building LibreOffice as root is a very
# bad idea"). Provision a regular user; /opt/emsdk and /opt/qt5-wasm
# are world-readable from earlier stages, so no further chowns needed.
RUN useradd -m -s /bin/bash builder \
    && mkdir -p /build/lo \
    && chown -R builder:builder /build /build/lo

USER builder
# Fixed working directory: paths bake into soffice.data, so keeping this
# stable across rebuilds keeps the artifact deterministic.
WORKDIR /build/lo

# Branch-clone then commit-checkout. git.libreoffice.org may not allow
# fetching arbitrary SHAs directly, so this dance is the safe form.
RUN git clone --branch "${LO_BRANCH}" https://git.libreoffice.org/core . \
    && git checkout "${LO_COMMIT}"

RUN bash -c 'source /opt/emsdk/emsdk_env.sh && \
    ./autogen.sh \
        --with-distro=LibreOfficeWASM32 \
        QT5DIR=/opt/qt5-wasm \
        --without-fonts \
        --without-help \
        --with-locales=ALL \
        --disable-extensions \
        --disable-lotuswordpro \
        --enable-ccache'

# Bundle-slimming flags (verified against configure.ac on the
# distro/allotropia/zeta-24-2 commit pinned in versions.json):
#
# --without-fonts        skip ~52 MB of bundled TTFs; client/ink
#                        injects system fonts at runtime.
# --without-help         drop the in-app help system; we never expose
#                        LO's UI so help is unreachable.
# --with-locales=ALL     bundle locale data (number/date/currency
#                        formats, collation) for every locale LO
#                        supports. WASM target with --enable-
#                        customtarget-components only accepts "all"
#                        or "en"; "ALL" gives full coverage so docx
#                        with non-English locale formatting renders
#                        correctly (e.g. comma decimal separators,
#                        non-Latin date formats).
# --disable-extensions   drop extension-loader plumbing.
# --disable-lotuswordpro drop the Lotus Word Pro import filter; we
#                        only convert .docx, never .lwp.
#
# --enable-mergelibs is incompatible with the above: its hardcoded
# library list references canvas/help/vba libs that --without-help
# and --disable-* remove. Tried separately, fails at make-time. Could
# be revisited by patching solenv/inc/Library_merged.mk to make those
# entries conditional, but out of scope here.

RUN bash -c 'source /opt/emsdk/emsdk_env.sh && make -j"$(nproc)"'

# ----- dist: stage outputs ------------------------------------------------
FROM ubuntu:24.04 AS dist
RUN mkdir -p /dist /dist/LICENSES

# Web root that zetajs expects. Contains soffice.{js,wasm,data,
# data.js,data.js.metadata} plus any other auxiliary files Emscripten
# emits — we copy the whole directory so future toolchain bumps that
# add a file don't silently break the runtime.
COPY --from=lo-stage /build/lo/workdir/installation/LibreOffice/emscripten/. /dist/

# Drop the standalone-app HTML entrypoint we don't use.
RUN rm -f /dist/qt_soffice.html

# License texts. Paths assume the standard layouts of the upstream repos
# at the pinned commits; if those move, adjust here and rebuild.
COPY --from=lo-stage /build/lo/instdir/LICENSE /dist/LICENSES/LibreOffice.txt
COPY --from=lo-stage /build/lo/instdir/NOTICE /dist/LICENSES/LibreOffice-NOTICE.txt
COPY --from=qt-stage /build/qt5/src/LICENSE.LGPLv3 /dist/LICENSES/Qt5.txt
COPY --from=emsdk-stage /opt/emsdk/upstream/emscripten/LICENSE /dist/LICENSES/Emscripten.txt

# Final sanity: list what we're shipping. Visible in `docker build` output.
RUN ls -la /dist /dist/LICENSES
