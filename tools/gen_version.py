#!/usr/bin/env python3
"""Compute the build version and generate include/wkali_version.h + assets/param.json.

Fork versioning (see FORK.md): the version shown everywhere and used as the
AppCache key is the fork's own semver, set by wkx-v* git tags:

    release:      1.2.3                    (tag wkx-v1.2.3, built by release.yml)
    pre-release:  1.2.3-beta.1             (tag wkx-v1.2.3-beta.1)
    dev:          1.2.3-4-gabc1234         (`git describe`, 0.0.0-dev with no tags)
    dirty dev:    1.2.3-4-gabc1234-dirty.20261002123500   (local builds only)

X_VERSION in the environment sets the version explicitly (CI always passes
it); otherwise tools/fork_version.sh dev computes it. The dirty suffix keeps
local rebuilds of an uncommitted tree on fresh AppCache URLs; it is never added
when X_VERSION is given.

The upstream PLK version (WKAL_VERSION in include/wkali.h) is only read, to
show "based on WebKit Autoloader vX". It is never written.

When CUSTOM_VERSION is set, it is appended (e.g. CUSTOM_VERSION=umtx2-test ->
1.2.3-umtx2-test) and also shown in the PS5 homescreen app title.

Usage:
    gen_version.py                 # (re)generate version header and app metadata
    gen_version.py --print         # print the full version string
    gen_version.py --print-x       # print the fork version (no dirty/custom suffix)
"""

import datetime
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEADER = os.path.join(REPO, "include", "wkali_version.h")
WKALI_H = os.path.join(REPO, "include", "wkali.h")
FORK_VERSION_SH = os.path.join(REPO, "tools", "fork_version.sh")
PARAM_JSON = os.path.join(REPO, "assets", "param.json")
PARAM_TEMPLATE = os.path.join(REPO, "assets", "param.json.template")
VERSION_PLACEHOLDER = b"[[VERSION_PLACEHOLDER]]"
# Replaced with upstream's WKAL_VERSION wherever the pages say "based on vX".
UPSTREAM_VERSION_PLACEHOLDER = b"[[UPSTREAM_VERSION_PLACEHOLDER]]"
PORT_PLACEHOLDER = b"[[PORT_PLACEHOLDER]]"


def read_upstream_version():
    """Read upstream's WKAL_VERSION from include/wkali.h (never edited here)."""
    try:
        with open(WKALI_H) as f:
            content = f.read()
        m = re.search(r'#define\s+WKAL_VERSION\s+"([^"]+)"', content)
        if m:
            return m.group(1)
    except OSError:
        pass
    return "0.0.0"


def read_port():
    """Read WKALI_PORT from include/wkali.h.

    The deeplink in param.json must point at the same port the installer serves
    on — the port is part of the AppCache origin, so a mismatch means the
    homescreen app opens a URL that was never cached. Substituting it from the
    header keeps the two from drifting.
    """
    with open(WKALI_H) as f:
        content = f.read()
    m = re.search(r"#define\s+WKALI_PORT\s+(\d+)", content)
    if not m:
        sys.exit("Error: could not find WKALI_PORT in include/wkali.h")
    return m.group(1)


def git(*args):
    """Run a git command in the repo; returns stdout stripped or ''."""
    try:
        return subprocess.run(
            ["git", *args], cwd=REPO, capture_output=True, text=True, errors="replace"
        ).stdout.strip()
    except OSError:
        return ""


def read_tag_prefix():
    """The release tag prefix, from PREFIX= in tools/fork_version.sh."""
    with open(FORK_VERSION_SH) as f:
        m = re.search(r"^PREFIX='([^']+)'", f.read(), re.M)
    if not m:
        sys.exit("Error: could not find PREFIX in tools/fork_version.sh")
    return m.group(1)


def read_fork_version():
    """The fork's own version: X_VERSION from the environment, else the same
    `git describe` that `tools/fork_version.sh dev` runs (done here directly so
    it also works where `bash` is not Git Bash, e.g. WSL's stub on Windows).
    Returns (version, explicit)."""
    explicit = os.environ.get("X_VERSION", "").strip()
    if explicit:
        return explicit, True
    prefix = read_tag_prefix()
    desc = git("describe", "--tags", "--match", prefix + "*")
    if desc.startswith(prefix):
        return desc[len(prefix):], False
    return "0.0.0-dev", False


def get_version_info():
    """Compute the version components. Returns a dict with 'full' being the
    version string used for the AppCache dir/key and the artifact names, and
    'x' the fork version shown to the user."""
    upstream = read_upstream_version()
    x_version, explicit = read_fork_version()
    custom = os.environ.get("CUSTOM_VERSION", "").strip()

    git_hash = git("rev-parse", "--short", "HEAD")
    dirty = git("status", "--porcelain")
    suffix = git_hash or "unknown"

    if explicit and "-" not in x_version:
        build_type = "release"
    elif explicit and re.search(r"-(alpha|beta|rc)\.\d+$", x_version):
        build_type = "prerelease"
    else:
        build_type = "dev"

    full = x_version
    if custom:
        full = f"{full}-{custom}"
    elif dirty and not explicit:
        suffix = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
        full = f"{full}-dirty.{suffix}"

    return {
        "x": x_version,
        "upstream": upstream,
        "base": upstream,
        "build_type": build_type,
        "suffix": suffix,
        "full": full,
        "git_hash": git_hash or "unknown",
        "dirty": bool(dirty),
        "build_time": datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y-%m-%d %H:%M:%S UTC"
        ),
        "title": full if custom else x_version,
    }


def header_text(info):
    return (
        "#pragma once\n"
        "/* Auto-generated by tools/gen_version.py - do not edit. */\n"
        "\n"
        f'#define WKAL_BASE_VERSION "{info["base"]}"  /* upstream PLK version */\n'
        f'#define WKAL_BUILD_TYPE "{info["build_type"]}"\n'
        f'#define WKAL_BUILD_SUFFIX "{info["suffix"]}"\n'
        f'#define WKAL_FULL_VERSION "{info["full"]}"\n'
        f'#define WKAL_BUILD_TIME "{info["build_time"]}"\n'
    )


def write_if_changed(path, data):
    """Write bytes only when the content differs, to avoid pointless rebuilds."""
    try:
        with open(path, "rb") as f:
            if f.read() == data:
                return
    except OSError:
        pass
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if argv and argv[0] == "--print":
        print(get_version_info()["full"])
        return 0
    if argv and argv[0] == "--print-x":
        print(get_version_info()["x"])
        return 0

    info = get_version_info()

    write_if_changed(HEADER, header_text(info).encode("utf-8"))

    # PS5 homescreen app metadata. The label is a fixed string ("Jailbreak"), so
    # VERSION_PLACEHOLDER is usually absent — bytes.replace is a no-op then, and
    # the substitution still works if a version is ever put back in the label.
    # PORT_PLACEHOLDER comes from WKALI_PORT so the deeplink and the server port
    # cannot drift apart.
    with open(PARAM_TEMPLATE, "rb") as f:
        param = f.read()
    param = param.replace(VERSION_PLACEHOLDER, info["title"].encode("utf-8"))
    param = param.replace(PORT_PLACEHOLDER, read_port().encode("utf-8"))
    write_if_changed(PARAM_JSON, param)
    return 0


if __name__ == "__main__":
    sys.exit(main())
