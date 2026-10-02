#!/bin/bash
# WebKit Autoloader X Installer - Versioned Release Build Script
#
# Version: X_VERSION from the environment (CI passes the release version or
# `tools/fork_version.sh dev`), else gen_version.py's `git describe` on the
# wkx-v* tags. ARTIFACT_SUFFIX (e.g. "-abc1234" for dev builds) is appended to
# the artifact names only:
#
#   webkit-autoloader-x-installer_v<version>[-<sha>]_ps5.elf
#   webkit-autoloader-x-host_v<version>[-<sha>]_pc.py

# 1. Compute full version
VERSION=$(python3 tools/gen_version.py --print)

if [ -z "$VERSION" ]; then
    echo "Error: Could not compute version"
    exit 1
fi

SUFFIX="${ARTIFACT_SUFFIX:-}"
OUTPUT_ELF="webkit-autoloader-x-installer_v${VERSION}${SUFFIX}_ps5.elf"
HOST_PY="webkit-autoloader-x-host_v${VERSION}${SUFFIX}_pc.py"
IMAGE_NAME="ps5-webkit-autoloader-sdk"

echo "--- Building WebKit Autoloader X Installer v$VERSION (based on WebKit Autoloader v$(bash tools/fork_version.sh upstream)) ---"

# 2. Remove old versioned artifacts
rm -f webkit-autoloader-x-installer_v*.elf webkit-autoloader-x-host_v*.py
echo "      Removed old artifacts (webkit-autoloader-x-installer_v*.elf, webkit-autoloader-x-host_v*.py)"

# 3. Build/verify the docker image (includes librsvg for icon generation)
if [[ "$(docker images -q $IMAGE_NAME 2> /dev/null)" == "" ]]; then
    echo "      Docker image $IMAGE_NAME not found. Building... (this may take a few minutes)"
    docker build -t $IMAGE_NAME -f Dockerfile.sdk .
    if [ $? -ne 0 ]; then
        echo "      !!! Docker image build FAILED!"
        exit 1
    fi
    echo "      Docker image built successfully."
fi

# 4. Build native ELF via Docker (generates icon assets + file registry as deps)
#    Note: docker does NOT inherit the host environment, so X_VERSION,
#    FORCE_EXPLOIT and CUSTOM_VERSION must be passed explicitly or defaults
#    (git describe/"auto"/empty) apply.
echo "[1/2] Building native ELF via Docker..."
docker run --rm -u "$(id -u):$(id -g)" -e "X_VERSION=${X_VERSION:-}" -e "FORCE_EXPLOIT=${FORCE_EXPLOIT:-auto}" -e "CUSTOM_VERSION=${CUSTOM_VERSION:-}" -v "$(pwd)":/src -w /src $IMAGE_NAME make clean all

if [ $? -ne 0 ]; then
    echo "      !!! ELF build FAILED!"
    exit 1
fi

if [ -f "installer.elf" ]; then
    mv installer.elf "$OUTPUT_ELF"
    echo "      Created versioned binary: $OUTPUT_ELF"
else
    echo "      !!! installer.elf not found after build!"
    exit 1
fi

# 5. Build standalone webkit-autoloader-host.py with the frontend embedded.
#    HOST_PAYLOAD points at the versioned installer ELF built in step 4 (the
#    PC host serves it as the autoload payload instead of the bundled one).
echo "[2/2] Building webkit-autoloader-host.py (embedded frontend)..."
make host HOST_PAYLOAD="$OUTPUT_ELF"
if [ $? -ne 0 ]; then
    echo "      !!! webkit-autoloader-host.py build FAILED!"
    exit 1
fi
mv webkit-autoloader-host.py "$HOST_PY"
echo "      Created: $HOST_PY"

echo "--- Build Complete! ---"
echo "Note: Windows executable (.exe) is built via GitHub Actions."
ls -la "$OUTPUT_ELF" "$HOST_PY"
