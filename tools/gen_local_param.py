#!/usr/bin/env python3
"""Generate assets/param_local.json for the "Jailbreak (Local)" installer.

The local variant is a shortcut-only build: it installs a homescreen app whose
deeplink points straight at a host on your LAN, with no on-console HTTP server
and no AppCache. Only the target host is configurable.

    LOCAL_HOST=192.168.1.50:8080 python3 tools/gen_local_param.py

LOCAL_HOST is "<host>:<port>" (or just "<host>" for port 80) and defaults to
DEFAULT_LOCAL_HOST below. The Makefile's `local` target runs this automatically.

Keep "titleId" in assets/param.local.json.template in sync with WKAL_TITLE_ID
in include/wkali.h under WKAL_VARIANT_LOCAL — app_installer.c builds the app's
install paths from the C constant while the metadata comes from the template.
"""
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(REPO, "assets", "param.local.json.template")
OUTPUT = os.path.join(REPO, "assets", "param_local.json")
WKALI_H = os.path.join(REPO, "include", "wkali.h")
PLACEHOLDER = "[[LOCAL_HOST_PLACEHOLDER]]"

DEFAULT_LOCAL_HOST = "192.168.1.139:6969"

# host[:port] — hostname/IPv4 plus an optional port. Deliberately strict: a bad
# value here produces an app tile that silently opens nothing.
HOST_RE = re.compile(r"^[A-Za-z0-9.\-]+(:\d{1,5})?$")


def expected_title_id():
    """WKAL_TITLE_ID from the WKAL_VARIANT_LOCAL branch of include/wkali.h."""
    with open(WKALI_H) as f:
        content = f.read()
    m = re.search(
        r"#ifdef\s+WKAL_VARIANT_LOCAL(.*?)#else", content, re.S
    )
    if not m:
        return None
    m2 = re.search(r'#define\s+WKAL_TITLE_ID\s+"([^"]+)"', m.group(1))
    return m2.group(1) if m2 else None


def main():
    host = os.environ.get("LOCAL_HOST", "").strip() or DEFAULT_LOCAL_HOST

    if host.startswith(("http://", "https://")):
        sys.exit(f"Error: LOCAL_HOST must be host[:port] without a scheme, got {host!r}")
    if not HOST_RE.match(host):
        sys.exit(f"Error: LOCAL_HOST {host!r} is not a valid host[:port].")
    if ":" in host:
        port = int(host.rsplit(":", 1)[1])
        if not 1 <= port <= 65535:
            sys.exit(f"Error: port {port} in LOCAL_HOST is out of range.")

    with open(TEMPLATE) as f:
        param = f.read()

    if PLACEHOLDER not in param:
        sys.exit(f"Error: {PLACEHOLDER} not found in {os.path.relpath(TEMPLATE, REPO)}")

    param = param.replace(PLACEHOLDER, host)

    # Fail loudly rather than shipping an app tile that opens nothing.
    data = json.loads(param)
    want = expected_title_id()
    if want and data["titleId"] != want:
        sys.exit(
            f"Error: titleId {data['titleId']!r} in the template does not match "
            f"WKAL_TITLE_ID {want!r} in include/wkali.h (WKAL_VARIANT_LOCAL)."
        )

    with open(OUTPUT, "w", newline="\n") as f:
        f.write(param)

    print(f"Wrote {os.path.relpath(OUTPUT, REPO)}")
    print(f"  titleId    : {data['titleId']}")
    print(f"  titleName  : {data['localizedParameters']['en-US']['titleName']}")
    print(f"  deeplinkUri: {data['deeplinkUri']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
