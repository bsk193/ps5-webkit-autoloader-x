# Fork notes

This repo is a fork of [itsPLK/ps5-webkit-autoloader](https://github.com/itsPLK/ps5-webkit-autoloader)
that loads [Payload Manager X](https://github.com/bsk193/ps5-payload-manager-x) instead of the
official Payload Manager.

## Dependency chain

```
bsk193/ps5-webkit-autoloader-x          (this repo — installer, "Jailbreak" app, version)
  ├─ itsPLK/ps5-webkit-remote-loader    (submodule, upstream as-is: exploit chains, installer C helpers, PC host)
  └─ autoload payload
     = bsk193/ps5-unified-autoloader-x  (fork: browser handling, app kill, autoload.txt)
        └─ always-launched manager
           = bsk193/ps5-payload-manager-x  (pldmgrx, HTTP port 8084)
```

Same layering as upstream, which autoloads `itsPLK/ps5-unified-autoloader` (→ official Payload
Manager). **No remote-loader fork is needed:** it is product-neutral and takes the embedded
payload (`--embed`), app name/title ID/icon (`include/installer_config.h`) and host name
(`--name`) from this repo; nothing in it refers to pldmgr, the port or the title.

No exploit or caching logic was modified in either fork. The one behavioural change is in
`ps5-unified-autoloader-x`: upstream launches the embedded manager **only** when no
`autoload.txt` is found, so a leftover config silently suppresses it. This fork always launches
it, treating `autoload.txt` as an additional payload chain rather than an alternative — its
payloads run first, then the manager starts after a 2 s pause
(`PLDMGRX_LAUNCH_DELAY_US` in `include/autoloader.h`).

## What actually changed here

Upstream 0.6.0 rebuilt the project on [ps5-webkit-remote-loader](https://github.com/itsPLK/ps5-webkit-remote-loader),
which now owns the exploit chains, the shared installer C code and the PC host builder. The fork
delta is correspondingly small:

| File | Change |
|---|---|
| `.gitmodules`, `third_party/` | `ps5-unified-autoloader` → `ps5-unified-autoloader-x` (`bsk193/…`) |
| `tools/download_deps.sh`, `Makefile` | payload submodule/repo and virtual ELF name point at the fork |
| `include/wkali.h` | `WKALI_PORT` → `18282`; `WKAL_TITLE_ID` → `WKLX00001`; `WKAL_APP_LABEL` "Jailbreak" (`WKAL_VERSION` stays upstream's) |
| `include/installer_config.h` | `INSTALLER_APP_NAME` → `WKAL_APP_LABEL` (remote-loader's installer notifications) |
| `assets/param.json.template` | `titleId` → `WKLX00001`, `titleName` → "Jailbreak", deeplink port from `WKALI_PORT` |
| `assets/icon.png`, `assets/icon.svg`, `tools/embed_icon_png.py`, `tools/gen_icons.py` | Homescreen tile icon: broken chain + globe badge (raster master, 512x512; badge kept clear of the tile's rounded corner). `embed_icon_png.py` wraps it into `icon.svg`; `gen_icons.py` uses it full-bleed (no padding) |
| `include/version_x.h`, `tools/fork_version.sh`, `tools/gen_version.py`, `tools/release.ps1` | Fork versioning (see below) |
| `src/main.c`, `frontend/*`, `tools/gen_file_registry.py` | Branding and "X vN, based on vX" version display |
| `frontend/autoloader/theme-x.{css,js}`, `<style id="theme-x">` in `frontend/installer-page/index.html` | Jailbreak shared UI (dark, flat, small radii, one accent), layered on upstream's styles via `PAGE_CSS`/`PAGE_JS`. The Y2JB fork draws the same UI with the same values |
| `assets/jb-logo.png`, `tools/embed_ui_logo.py` | Plain Jailbreak icon shown inside the UI (no badge; the badge is only for telling the homescreen tiles apart). The script inlines it into the installer page and theme-x.css |
| `build_release.sh`, `.gitignore`, `.github/workflows/` | Artifact names; `build.yml` (every push/PR) and tag-driven `release.yml` |
| `README.md`, `ARCHITECTURE.md` | Fork notes |

`WKAL_TITLE_ID` and `param.json.template`'s `titleId` **must always match** — the installer
builds the app's install paths from the C constant while the metadata comes from the template.

## Coexisting with upstream

|  | Upstream PLK | This fork |
|---|---|---|
| Title ID | `WKAL00001` | `WKLX00001` |
| Homescreen label | WebKit Autoloader | Jailbreak |
| Deeplink | `127.0.0.1:18181/app/index.html` | `127.0.0.1:18282/app/index.html` |
| Installer HTTP server | port 18181 | port 18282 |
| Artifact | upstream's | `webkit-autoloader-x-installer_v*.elf` |

Two things must differ for both to coexist:

- **Title ID** — the app is installed to `/user/app/<title_id>/`, so a shared ID means one
  app overwrites the other.
- **Port** — AppCache is keyed by origin, and the port is part of the origin. Upstream and
  this fork both cache a page at `127.0.0.1:<port>/app/index.html`; on a shared port they
  would share one cache entry and each launch would clobber the other's cached autoloader.
  That is why this fork moved to **18282**.

`WKALI_PORT` in `include/wkali.h` is the single source of truth for the port —
`gen_version.py` substitutes it into the deeplink via `[[PORT_PLACEHOLDER]]`, so the served
port and the deeplink cannot drift apart.

> Moving off 18181 orphans any AppCache a previous build of this fork left at the old port.
> Re-running the installer (which you do to update anyway) caches fresh at 18282; the stale
> 18181 entry is simply no longer referenced.

### Coexistence vs. drop-in

The title ID is deliberately different from upstream's `WKAL00001`, so this installs as a
**second** homescreen app next to the official autoloader. To make it a true drop-in replacement
that overwrites the official app instead, set **both** values back to `WKAL00001`.

## Versioning

The fork has its **own semver**, set by git tags with the prefix **`x-v`**, the same prefix as
every bsk193 `-x` fork ([pkg-manager-x](https://github.com/bsk193/pkg-manager-x),
payload-manager-x, ps5-y2jb-autoloader-x). It never collides with upstream's `v*` tags, which
are fetched into the same clone.

| Tag | Result |
|---|---|
| `x-v1.2.3` | Release, marked **Latest** on GitHub |
| `x-v1.2.3-alpha.N` / `-beta.N` / `-rc.N` | Pre-release, not Latest. The dot before `N` is required so `beta.10` sorts after `beta.9` |

Rules:

1. **`WKAL_VERSION` in `include/wkali.h` is upstream's and is never edited.** It is only read,
   to show "based on WebKit Autoloader vX". Merging upstream then never conflicts on the
   version line.
2. **Releases come only from commits on `main`.** `release.yml` refuses anything else.
3. **The build compiles the version in.** Release builds get the tag's version; other builds
   use `git describe` (e.g. `1.0.0-4-g52ed3fe`), and `0.0.0-dev` with no `x-v*` tags at all.

Where it lives:

| File | Role |
|---|---|
| `tools/fork_version.sh` | `upstream` / `dev` / `parse <tag>`; holds the `x-v` prefix |
| `include/version_x.h` | `WKAL_X_VERSION` (our semver, `-DWKAL_X_VERSION` from the Makefile) and `WKAL_X_VERSION_UPSTREAM` |
| `tools/gen_version.py` | Full build version (`X_VERSION` env, else `git describe`); also the AppCache key |
| `tools/release.ps1` | Computes the next version, checks, creates and pushes the tag |

The fork version is what the installer log, the "cached successfully" notification, the page
titles/footers and the PC host banner show, each followed by "based on WebKit Autoloader vX".
The ELF carries a fork marker `WKALI_X_VER:<ver> WKALI_X_BASE:<upstream>` next to upstream's
unchanged `WKALI_VER:` marker.

The fork version is also the **AppCache key** (`/app/<version>/`, `?v=<version>`): every new tag
caches fresh, independent of whether upstream bumped. Local builds from an uncommitted tree add
`-dirty.<timestamp>` so rebuilds still re-cache; CI never does.

Artifacts: `webkit-autoloader-x-installer_v<ver>[-<sha>]_ps5.elf`,
`webkit-autoloader-x-host_v<ver>[-<sha>]_pc.py` and `..._windows.exe`. Dev builds carry the
`-<sha>` suffix.

The PC host's update check follows this fork's **Latest** release (`x-v*`), not PLK's.

> History: `wkx-v1.0.0` was the first fork-semver release (the prefix was `wkx-v` until it
> was unified to `x-v`; `x-v1.0.0` marks the same commit). Before that, the fork edited `WKAL_VERSION` to `<PLK version>.<build>x`
> (`0.3.0.1x` … `0.4.0.3x`). Those `v*x` tags and releases remain as they are.

## Release procedure

`tools/download_deps.sh` resolves the payload with `git describe --tags` on the
`third_party/ps5-unified-autoloader-x` submodule and then downloads the GitHub **release** with
that exact tag. So the releases must be cut bottom-up:

**1. Payload Manager X** (only when the manager itself changes)

Tag `x-v*` with its `tools/release.ps1`; the release publishes one `pldmgrx_v<ver>.elf`
(built with `PLDMGRX=1 PLDMGRX_PORT=8084`).

**2. ps5-unified-autoloader-x**

Merge to its `main`, then tag `x-v*` with its `tools/release.ps1` (same scheme as this repo).
The release builds against the **latest** published `pldmgrx_v*.elf` and publishes
`ps5-unified-autoloader-x_v<ver>_ps5.elf`.

> Its build downloads the latest pldmgrx release; it does **not** use its
> `third_party/ps5-payload-manager-x` submodule, which only matters for `./build_release.sh -b`
> (source builds). Releases before `x-v1.0.0` were `v<PLK version>.<build>x-<sha>`.

**3. This repo**

Point the submodule at the tag that step 2 just created, then release:

```bash
git submodule update --init --recursive
git -C third_party/ps5-unified-autoloader-x fetch --tags
git -C third_party/ps5-unified-autoloader-x checkout x-v<version from step 2>
git commit -am "build(deps): bump ps5-unified-autoloader-x"
git push fork main
```

Then tag it from an up-to-date `main` with `tools/release.ps1` (PowerShell):

| Command | Result |
|---|---|
| `-Bump patch\|minor\|major` | stable release |
| `-Bump minor -Pre beta` | `x.y.0-beta.1` |
| `-Pre beta` / `-Pre rc` | continues the pending pre-release |
| `-Promote` | current pre-release becomes stable |
| `-Version 1.2.3[-beta.1]` | that exact version |
| `-DryRun` | shows what would happen |
| `-Yes` | skips the confirmation prompt |

It pushes only the `x-v*` tag; the **Release** workflow builds and publishes it. Alternatively,
run **Release** from the Actions tab on `main` and enter the version.

> If `download_deps.sh` reports "could not fetch release", the submodule is checked out at an
> untagged commit or the corresponding release has not been published yet. `git describe --tags`
> inside the submodule tells you which tag it resolved to.

## Syncing with upstream

```bash
git fetch upstream
git merge upstream/main
```

The "based on" version follows automatically; the fork version changes only when a new
`x-v*` tag is pushed.

Expect conflicts only in the files listed above. The exploit patches (`patches/`), the frontend
and the caching logic are untouched by this fork, so they should merge cleanly.

Remotes: `upstream` = itsPLK (read-only), `fork` = bsk193.
