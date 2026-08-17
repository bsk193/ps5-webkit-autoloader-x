#!/bin/bash
# WebKit Autoloader X Installer - Versioned Release Build Script

# 1. Compute full version (stable = base, dev = base + build type + git hash/timestamp)
VERSION=$(python3 tools/gen_version.py --print)

if [ -z "$VERSION" ]; then
    echo "Error: Could not compute version"
    exit 1
fi

OUTPUT_ELF="webkit-autoloader-installer_v${VERSION}.elf"
LOCAL_ELF_OUT="jailbreak-local-installer_v${VERSION}.elf"
HOST_PY="webkit-autoloader-host_v${VERSION}.py"
IMAGE_NAME="ps5-webkit-autoloader-sdk"

# Host[:port] baked into the "Jailbreak (Local)" shortcut.
LOCAL_HOST="${LOCAL_HOST:-192.168.1.139:6969}"

echo "--- Building WebKit Autoloader X Installer v$VERSION ---"

# 2. Remove old versioned artifacts
rm -f webkit-autoloader-installer_v*.elf webkit-autoloader-host_v*.py \
      jailbreak-local-installer_v*.elf
echo "      Removed old artifacts (webkit-autoloader-installer_v*.elf, jailbreak-local-installer_v*.elf, webkit-autoloader-host_v*.py)"

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
#    Note: docker does NOT inherit the host environment, so BUILD_TYPE,
#    FORCE_EXPLOIT and CUSTOM_VERSION must be passed explicitly or defaults
#    ("dev"/"auto"/empty) apply.
echo "[1/3] Building native ELF via Docker..."
docker run --rm -u "$(id -u):$(id -g)" -e "BUILD_TYPE=${BUILD_TYPE:-dev}" -e "FORCE_EXPLOIT=${FORCE_EXPLOIT:-auto}" -e "CUSTOM_VERSION=${CUSTOM_VERSION:-}" -v "$(pwd)":/src -w /src $IMAGE_NAME make clean all

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

# 4b. Build the "Jailbreak (Local)" shortcut-only installer. Separate optional
#     download — it is NOT bundled into the host script or the normal ELF.
echo "[2/3] Building the Jailbreak (Local) installer (-> http://${LOCAL_HOST})..."
docker run --rm -u "$(id -u):$(id -g)" -e "BUILD_TYPE=${BUILD_TYPE:-dev}" -e "CUSTOM_VERSION=${CUSTOM_VERSION:-}" -e "LOCAL_HOST=${LOCAL_HOST}" -v "$(pwd)":/src -w /src $IMAGE_NAME make local LOCAL_HOST="${LOCAL_HOST}"

if [ $? -ne 0 ]; then
    echo "      !!! Local installer build FAILED!"
    exit 1
fi

if [ -f "installer-local.elf" ]; then
    mv installer-local.elf "$LOCAL_ELF_OUT"
    echo "      Created versioned binary: $LOCAL_ELF_OUT"
else
    echo "      !!! installer-local.elf not found after build!"
    exit 1
fi

# 5. Build standalone webkit-autoloader-host.py with the frontend embedded.
#    HOST_PAYLOAD points at the versioned installer ELF built in step 4 (the
#    PC host serves it as the autoload payload instead of the bundled one).
echo "[3/3] Building webkit-autoloader-host.py (embedded frontend)..."
make host HOST_PAYLOAD="$OUTPUT_ELF"
if [ $? -ne 0 ]; then
    echo "      !!! webkit-autoloader-host.py build FAILED!"
    exit 1
fi
mv webkit-autoloader-host.py "$HOST_PY"
echo "      Created: $HOST_PY"

echo "--- Build Complete! ---"
echo "Note: Windows executable (.exe) is built via GitHub Actions."
ls -la "$OUTPUT_ELF" "$LOCAL_ELF_OUT" "$HOST_PY"

