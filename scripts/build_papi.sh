#!/bin/bash
# Build script for PAPI (Performance API) from GitHub
set -e

BUILD_ROOT="$(pwd)/build/papi"
INSTALL_DIR="$BUILD_ROOT/papi-install"
SRC_DIR="$BUILD_ROOT/papi-src"
PAPI_REPO="https://github.com/icl-utk-edu/papi.git"
PAPI_CLONE_DIR="$SRC_DIR/papi"
PACKAGE_ROOT="$(pwd)"
PAPI_TAG="papi-7-2-0-t"   

mkdir -p "$BUILD_ROOT" "$INSTALL_DIR" "$SRC_DIR"

# Clone PAPI repo if not already present
if [ ! -d "$PAPI_CLONE_DIR" ]; then
  echo "[INFO] Cloning PAPI repo at tag $PAPI_TAG..."
  git clone --branch "$PAPI_TAG" --depth 1 "$PAPI_REPO" "$PAPI_CLONE_DIR"
fi

cd "$PAPI_CLONE_DIR/src"

# Configure with prefix to install into staging directory
./configure --prefix="$INSTALL_DIR"

# Build and install
make -j"$(nproc)"
make install

# Record version
cd "$PAPI_CLONE_DIR"
PAPI_VERSION=$(git describe --tags --always)
echo "$PAPI_VERSION" > "$INSTALL_DIR/PAPI.version"

# Copy staged PAPI install into package root
if [ -d "$INSTALL_DIR" ]; then
  cp -a "$INSTALL_DIR" "$PACKAGE_ROOT/"
fi

echo "[INFO] PAPI built and staged at $INSTALL_DIR (version $PAPI_VERSION)."