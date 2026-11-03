#!/usr/bin/env bash
# Build the versioned installer ELF and standalone PC setup host.
#
# Version: X_VERSION from the environment (CI passes the release version or
# `tools/fork_version.sh dev`), else gen_version.py's `git describe` on the
# x-v* tags. ARTIFACT_SUFFIX (e.g. "-abc1234" for dev builds) is appended to
# the artifact names only:
#
#   webkit-autoloader-x-installer_v<version>[-<sha>]_ps5.elf
#   webkit-autoloader-x-host_v<version>[-<sha>]_pc.py
set -euo pipefail
cd "$(dirname "$0")"
if [ "$#" -ne 0 ]; then
    echo "Usage: X_VERSION=<version> ARTIFACT_SUFFIX=<suffix> CUSTOM_VERSION=<suffix> ./build_release.sh" >&2
    exit 1
fi
BUILD_VERSION="$(python3 tools/gen_version.py --print)"
if [ -z "$BUILD_VERSION" ]; then
    echo "Error: Could not compute version" >&2
    exit 1
fi
export BUILD_VERSION
SUFFIX="${ARTIFACT_SUFFIX:-}"
OUTPUT_ELF="webkit-autoloader-x-installer_v${BUILD_VERSION}${SUFFIX}_ps5.elf"
HOST_PY="webkit-autoloader-x-host_v${BUILD_VERSION}${SUFFIX}_pc.py"
IMAGE_NAME="ps5-webkit-autoloader-sdk"

# Remove previous versioned release outputs before rebuilding.
rm -f webkit-autoloader-x-installer_v*.elf webkit-autoloader-x-host_v*.py

if [ -z "$(docker images -q "$IMAGE_NAME")" ]; then
    docker build -t "$IMAGE_NAME" -f third_party/ps5-webkit-remote-loader/Dockerfile.sdk third_party/ps5-webkit-remote-loader
fi
docker run --rm -u "$(id -u):$(id -g)" \
    -e BUILD_VERSION -e "X_VERSION=${X_VERSION:-}" -e "CUSTOM_VERSION=${CUSTOM_VERSION:-}" \
    -v "$(pwd)":/src -w /src "$IMAGE_NAME" make clean all
mv installer.elf "$OUTPUT_ELF"
make host HOST_PAYLOAD="$OUTPUT_ELF"
mv webkit-autoloader-host.py "$HOST_PY"
echo "Built $OUTPUT_ELF and $HOST_PY (Windows .exe is built by GitHub Actions)."
