#!/usr/bin/env bash
# WebKit Autoloader X version helper.
#
#   tools/fork_version.sh upstream        upstream WKAL_VERSION (include/wkali.h), e.g. 0.5.2
#   tools/fork_version.sh dev             version for non-release builds, from `git describe`
#                                         (e.g. 1.1.0-3-gabc1234, or 0.0.0-dev without tags)
#   tools/fork_version.sh parse <tag>     validates a release tag and prints
#                                         "<version> <release|prerelease>"
#
# Release tags:  wkx-vMAJOR.MINOR.PATCH                   -> release (marked Latest)
#                wkx-vMAJOR.MINOR.PATCH-(alpha|beta|rc).N -> pre-release
#
# The prefix is "wkx-v" so it never collides with upstream PLK's "v*" tags
# (fetched into the same clone) or with the other -x forks' prefixes.
set -euo pipefail
cd "$(dirname "$0")/.."

PREFIX='wkx-v'
TAG_RE="^${PREFIX}(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(alpha|beta|rc)\.(0|[1-9][0-9]*))?$"

case "${1:-}" in
    upstream)
        UP=$(sed -n 's/^#define WKAL_VERSION "\(.*\)".*/\1/p' include/wkali.h | tr -d '\r')
        [ -n "$UP" ] || { echo "WKAL_VERSION not found in include/wkali.h" >&2; exit 1; }
        echo "$UP"
        ;;
    dev)
        DESC=$(git describe --tags --match "${PREFIX}*" 2>/dev/null || true)
        if [ -n "$DESC" ]; then echo "${DESC#"$PREFIX"}"; else echo "0.0.0-dev"; fi
        ;;
    parse)
        TAG="${2:-}"
        if ! [[ "$TAG" =~ $TAG_RE ]]; then
            echo "Invalid release tag '$TAG': use ${PREFIX}1.2.3 or ${PREFIX}1.2.3-beta.1 (alpha/beta/rc)" >&2
            exit 1
        fi
        VER="${TAG#"$PREFIX"}"
        if [[ "$VER" == *-* ]]; then echo "$VER prerelease"; else echo "$VER release"; fi
        ;;
    *)
        echo "usage: $0 upstream | dev | parse <tag>" >&2
        exit 1
        ;;
esac
