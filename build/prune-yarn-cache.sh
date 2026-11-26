#!/bin/bash
# Remove zips from the project-local yarn cache (/overleaf/.yarn/cache) that the
# Plug'n'Play map no longer references.
#
# Upstream runs `yarn workspaces focus --all --production` after building the
# frontend. That rewrites .pnp.cjs to production dependencies only, but leaves
# the zips of all dev/frontend dependencies in the cache, because yarn.lock
# still lists them. At runtime only packages referenced by .pnp.cjs can be
# resolved, so the remaining zips are dead weight.
#
# This must run inside the same RUN instruction that filled the cache,
# otherwise the deleted files still take up space in a lower image layer.
set -euo pipefail

ROOT=${1:-/overleaf}
CACHE="$ROOT/.yarn/cache"
cd "$ROOT"

if [ ! -d "$CACHE" ]; then
  echo "prune-yarn-cache: $CACHE does not exist, nothing to do"
  exit 0
fi

maps=(.pnp.cjs)
[ -f .pnp.data.json ] && maps+=(.pnp.data.json)

used=$(mktemp)
all=$(mktemp)
unused=$(mktemp)
trap 'rm -f "$used" "$all" "$unused"' EXIT

# Matches both direct references (./.yarn/cache/<zip>/node_modules/...) and
# virtual ones (./.yarn/__virtual__/<name>/<n>/cache/<zip>/node_modules/...).
grep -ohE 'cache/[^/"]+\.zip' "${maps[@]}" | sed 's#^cache/##' | sort -u > "$used"
find "$CACHE" -maxdepth 1 -type f -name '*.zip' -printf '%f\n' | sort > "$all"
comm -23 "$all" "$used" > "$unused"

n_all=$(wc -l < "$all")
n_used=$(wc -l < "$used")
n_unused=$(wc -l < "$unused")
n_missing=$(comm -13 "$all" "$used" | wc -l)

# Safety net: if the reference format of .pnp.cjs ever changes, the grep above
# would match (almost) nothing and we would delete the whole cache.
if [ "$n_used" -lt 100 ]; then
  echo "prune-yarn-cache: only $n_used referenced zips found in ${maps[*]} - refusing to prune" >&2
  exit 1
fi

if [ "$n_missing" -ne 0 ]; then
  echo "prune-yarn-cache: warning: $n_missing referenced zips are not in the cache:" >&2
  comm -13 "$all" "$used" | head -20 >&2
fi

before=$(du -sb "$CACHE" | cut -f1)
(cd "$CACHE" && xargs -r -d '\n' rm -f -- < "$unused")
after=$(du -sb "$CACHE" | cut -f1)

echo "prune-yarn-cache: $n_all zips, $n_used referenced, removed $n_unused" \
  "($(numfmt --to=iec "$before") -> $(numfmt --to=iec "$after"))"
