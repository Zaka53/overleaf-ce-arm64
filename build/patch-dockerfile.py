#!/usr/bin/env python3
"""Patch upstream server-ce/Dockerfile for the arm64 build.

- Run build/prune-yarn-cache.sh at the end of the `genScript install` and
  `genScript compile` steps (same RUN instruction, so the space is really freed).
- Give each Yarn Classic process its own cache folder during the compile step
  (build/yarn-classic-isolate-cache.cjs), fixing a race when Yarn 4 packs
  several Yarn-1 git dependencies in parallel.
- Print yarn's git-dependency pack logs if the compile step fails (they live in
  a tmpfs and are lost otherwise).

Fails loudly if upstream changed the lines we patch, instead of silently
building an unpatched image.
"""
import sys

PRUNE_MOUNT = (
    "--mount=type=bind,source=.arm64/build/prune-yarn-cache.sh,"
    "target=/run/prune-yarn-cache.sh"
)
ISOLATE_MOUNT = (
    "--mount=type=bind,source=.arm64/build/yarn-classic-isolate-cache.cjs,"
    "target=/run/yarn-classic-isolate-cache.cjs"
)

PATCHES = [
    (
        "    --mount=type=tmpfs,target=/tmp node genScript install | bash\n",
        "    --mount=type=tmpfs,target=/tmp \\\n"
        f"    {PRUNE_MOUNT} \\\n"
        "    node genScript install | bash && bash /run/prune-yarn-cache.sh\n",
    ),
    (
        "    node genScript compile | bash\n",
        f"    {PRUNE_MOUNT} \\\n"
        f"    {ISOLATE_MOUNT} \\\n"
        '    { export NODE_OPTIONS="--require /run/yarn-classic-isolate-cache.cjs"; \\\n'
        "      node genScript compile | bash || { cat /tmp/xfs-*/pack.log 2>/dev/null; exit 1; }; } \\\n"
        "    && bash /run/prune-yarn-cache.sh\n",
    ),
]


def main(path: str) -> None:
    with open(path) as f:
        content = f.read()
    for old, new in PATCHES:
        count = content.count(old)
        if count != 1:
            sys.exit(
                f"patch-dockerfile: expected exactly one occurrence of {old!r} "
                f"in {path}, found {count}. Upstream Dockerfile changed?"
            )
        content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print(f"patch-dockerfile: patched {path}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "server-ce/Dockerfile")
