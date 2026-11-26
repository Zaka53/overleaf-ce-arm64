# Overleaf CE – arm64

Unofficial `linux/arm64` builds of [Overleaf Community Edition](https://github.com/overleaf/overleaf).

This repository contains **no Overleaf source code**. A GitHub Actions workflow checks out
`overleaf/overleaf` at build time, builds `server-ce/Dockerfile-base` and `server-ce/Dockerfile`
natively on a GitHub-hosted ARM runner (`ubuntu-24.04-arm`) and pushes the result to GHCR.

## Image

```
ghcr.io/<owner>/overleaf-ce-arm64:latest     # latest build of upstream main
ghcr.io/<owner>/overleaf-ce-arm64:<sha7>     # pinned to an upstream commit
ghcr.io/<owner>/overleaf-ce-arm64:<YYYYMMDD> # build date
```

The image is a drop-in replacement for `sharelatex/sharelatex`.

## Builds

- **Scheduled:** every Monday 03:00 UTC from upstream `main`. Skipped if an image for that upstream commit already exists.
- **Manual:** *Actions → Build Overleaf CE (arm64) → Run workflow*
  - `ref` – upstream branch or commit SHA (default `main`; only `main` updates `:latest`)
  - `force` – rebuild even if the commit was already built
  - `texlive_mirror` – alternative TeX Live `tlnet` mirror, if the default CTAN mirror fails

## Usage

### With the Overleaf Toolkit

In `config/overleaf.rc`:

```
OVERLEAF_IMAGE_NAME=ghcr.io/<owner>/overleaf-ce-arm64
```

and set `config/version` to the tag you want (e.g. `latest` or a `<sha7>` tag).

### With docker compose

Replace the `image:` of the `sharelatex` service with `ghcr.io/<owner>/overleaf-ce-arm64:latest`.
MongoDB and Redis already ship official arm64 images.

## Notes

- Upstream `overleaf/overleaf` has no release tags for CE versions; pin a `<sha7>` tag for reproducible deployments.
- The image contains only TeX Live `scheme-basic` (same as upstream). Install more packages with `tlmgr` or build a derived image.
- After the first push, make the GHCR package public under *Package settings* if you want to pull without logging in.
- Overleaf is licensed under AGPL-3.0; this repository only provides build automation.
