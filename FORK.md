# Fork notes

This repo is a fork of [itsPLK/ps5-webkit-autoloader](https://github.com/itsPLK/ps5-webkit-autoloader)
that loads [Payload Manager X](https://github.com/bsk193/ps5-payload-manager-x) instead of the
official Payload Manager.

## Dependency chain

```
bsk193/ps5-webkit-autoloader-x          (this repo — exploit chain + installer)
  └─ payload.elf
     = bsk193/ps5-unified-autoloader-x  (fork: browser handling, app kill, autoload.txt)
        └─ always-launched manager
           = bsk193/ps5-payload-manager-x  (pldmgrx, HTTP port 8084)
```

No exploit or caching logic was modified in either fork. The one behavioural change is in
`ps5-unified-autoloader-x`: upstream launches the embedded manager **only** when no
`autoload.txt` is found, so a leftover config silently suppresses it. This fork always launches
it, treating `autoload.txt` as an additional payload chain rather than an alternative — its
payloads run first, then the manager starts after a 2 s pause
(`PLDMGRX_LAUNCH_DELAY_US` in `include/autoloader.h`).

## What actually changed here

| File | Change |
|---|---|
| `.gitmodules` | `third_party/ps5-unified-autoloader` → `third_party/ps5-unified-autoloader-x` (`bsk193/…`) |
| `tools/download_deps.sh` | `PAYLOAD_SUBMODULE` / `PAYLOAD_REPO` point at the fork |
| `include/wkali.h` | `WKAL_VERSION` → `0.3.1x`; `WKAL_TITLE_ID` → `WKLX00001` |
| `assets/param.json.template` | `titleId` → `WKLX00001`, `titleName` → "Jailbreak" (no version suffix) |
| `assets/icon.svg` | Replaced with a broken-chain-link jailbreak icon |
| `README.md`, `ARCHITECTURE.md` | Fork notes, branding, links |
| Misc source/build files | Branding strings only ("WebKit Autoloader" → "WebKit Autoloader X") |

The homescreen label is plain **"Jailbreak"** with no version. `gen_version.py` substitutes
`[[VERSION_PLACEHOLDER]]` in the template; the placeholder is simply absent now, and
`bytes.replace` on a missing needle is a no-op, so nothing breaks.

All derived icon assets (`icon0.png`, `icon.ico`, the two `favicon.svg`s and the two
`logo.svg`s) are generated from `assets/icon.svg` by `tools/gen_icons.py` via `make icons`,
which needs `rsvg-convert` — present in the SDK Docker image used by CI. Keep the master art
inside a circle of radius ~510 centred on (512, 512); `gen_icons.py`'s `ART_RADIUS` constant
assumes that extent when it computes padding.

`WKAL_TITLE_ID` and `param.json.template`'s `titleId` **must always match** — `app_installer.c`
builds the app's install paths from the C constant while the metadata comes from the template.

### Coexistence vs. drop-in

The title ID is deliberately different from upstream's `WKAL00001`, so this installs as a
**second** homescreen app next to the official autoloader. To make it a true drop-in replacement
that overwrites the official app instead, set **both** values back to `WKAL00001`.

## Release procedure

`tools/download_deps.sh` resolves the payload with `git describe --tags` on the
`third_party/ps5-unified-autoloader-x` submodule and then downloads the GitHub **release** with
that exact tag. So the releases must be cut bottom-up:

**1. Payload Manager X** (only when the manager itself changes)

Push a `v*` tag; its `release.yml` builds `pldmgrx_<tag>.elf` with `PLDMGRX=1 PLDMGRX_PORT=8084`.

**2. ps5-unified-autoloader-x**

```bash
cd ../ps5-unified-autoloader-x
# optional: bump the embedded manager
git -C third_party/ps5-payload-manager-x fetch --tags
git -C third_party/ps5-payload-manager-x checkout v0.5.1.2x   # or newer
git commit -am "deps: bump Payload Manager X"
git push fork main
```

Then run its **release** workflow (`workflow_dispatch`). It tags
`v<AUTOLOADER_VERSION>-<short-sha>` and publishes `ps5-unified-autoloader-x-v*.elf`.

> Its default build path downloads the latest published `pldmgrx_v*.elf` — it does **not** use
> the submodule. The submodule pin only matters for `./build_release.sh -b` (source builds).

**3. This repo**

Point the submodule at the tag that step 2 just created, then release:

```bash
git submodule update --init --recursive
git -C third_party/ps5-unified-autoloader-x fetch --tags
git -C third_party/ps5-unified-autoloader-x checkout v0.1.4x-<sha>
git commit -am "deps: bump ps5-unified-autoloader-x"
git push fork main
```

Then run this repo's **Release On-Demand** workflow. It refuses to run if a release for
`v$WKAL_VERSION` already exists, so bump `WKAL_VERSION` in `include/wkali.h` first when
re-releasing.

> If `download_deps.sh` reports "could not fetch release", the submodule is checked out at an
> untagged commit or the corresponding release has not been published yet. `git describe --tags`
> inside the submodule tells you which tag it resolved to.

## Syncing with upstream

```bash
git fetch upstream
git merge upstream/main
```

Expect conflicts only in the files listed above. The exploit patches (`patches/`), the frontend
and the caching logic are untouched by this fork, so they should merge cleanly.

Remotes: `upstream` = itsPLK (read-only), `fork` = bsk193.
