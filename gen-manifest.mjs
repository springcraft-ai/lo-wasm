#!/usr/bin/env node
// Walk the dist directory and emit a manifest as JSON to stdout:
//
//   {
//     builtAt: "2026-...Z",
//     versions: { loCore, emsdk, qt5, zetajsNpm },
//     files: [{ path, size, sha256 }, ...]
//   }
//
// Consumers (client/ink/scripts/fetch-lo-wasm.mjs) cross-check files in the
// extracted tarball against this manifest's per-file sha256s.

import { createHash } from 'node:crypto'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'

const DIST = process.argv[2] || 'dist'

function walk(dir) {
    const out = []
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (entry.name === 'manifest.json') continue
        const full = join(dir, entry.name)
        if (entry.isDirectory()) {
            out.push(...walk(full))
        } else if (entry.isFile()) {
            const buf = readFileSync(full)
            out.push({
                path: relative(DIST, full).split('\\').join('/'),
                size: buf.length,
                sha256: createHash('sha256').update(buf).digest('hex'),
            })
        }
    }
    return out
}

const versions = JSON.parse(readFileSync('versions.json', 'utf-8'))

const manifest = {
    builtAt: new Date().toISOString(),
    versions: {
        loCore: versions.loCore,
        loBranch: versions.loBranch,
        emsdk: versions.emsdk,
        emsdkBranch: versions.emsdkBranch,
        qt5: versions.qt5,
        qt5Branch: versions.qt5Branch,
        zetajsNpm: versions.zetajsNpm,
    },
    files: walk(DIST).sort((a, b) => a.path.localeCompare(b.path)),
}

process.stdout.write(JSON.stringify(manifest, null, 2) + '\n')
