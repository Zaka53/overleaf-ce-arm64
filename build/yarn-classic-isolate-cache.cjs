// Preloaded via NODE_OPTIONS during the upstream `genScript compile` step.
//
// Yarn 4 packs git dependencies that use a Yarn 1 lockfile (e.g. overleaf's
// codemirror forks) by running Yarn Classic (.yarn/releases/yarn-classic.cjs
// inside the cloned repo) - several of them in parallel. All of these Yarn
// Classic processes share the same cache folder and race while extracting the
// same tarballs ("Extracting tar content ... the file appears to be corrupt").
// Yarn Classic only accepts --mutex on the command line, so give every Yarn
// Classic process its own cache folder instead.
//
// Only Yarn Classic is touched: Yarn 4 also reads YARN_CACHE_FOLDER, and
// changing it there would move the project's PnP cache out of the image.
'use strict'

const script = process.argv[1] || ''
if (/[\\/]yarn-classic\.cjs$/.test(script)) {
  const base = process.env.YARN_CLASSIC_CACHE_BASE || '/root/.cache/yarn-classic'
  process.env.YARN_CACHE_FOLDER = `${base}/${process.pid}`
}
