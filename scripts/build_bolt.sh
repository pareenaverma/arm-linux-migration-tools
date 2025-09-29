#!/bin/bash
# Build script for BOLT (download and extract binary release)
set -e

BOLT_VERSION="19.1.7"
# BOLT_TAR="clang+llvm-${BOLT_VERSION}-aarch64-linux-gnu.tar.xz"
# BOLT_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${BOLT_VERSION}/${BOLT_TAR}"
ARCH=$(uname -m)
case "$ARCH" in
  aarch64|arm64)
    BOLT_TAR="clang+llvm-${BOLT_VERSION}-aarch64-linux-gnu.tar.xz"
    ;;
  x86_64|amd64)
    BOLT_TAR="LLVM-${BOLT_VERSION}-Linux-X64.tar.xz"
    ;;
  *)
    echo "[ERROR] Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

BOLT_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${BOLT_VERSION}/${BOLT_TAR}"
BOLT_DIR="bolt-bin"

if [ ! -f "$BOLT_TAR" ]; then
  echo "[INFO] Downloading BOLT binary release..."
  wget -q "$BOLT_URL"
fi

if [ -d "$BOLT_DIR" ]; then
  rm -rf "$BOLT_DIR"
fi
mkdir "$BOLT_DIR"
tar xf "$BOLT_TAR" --strip-components=1 -C "$BOLT_DIR"

# Copy BOLT executables into bolt-tools directory
BOLT_BIN_DIR="bolt-bin/bin"
if [ -d "$BOLT_BIN_DIR" ]; then
  mkdir -p bolt-tools
  cp "$BOLT_BIN_DIR/llvm-bolt" bolt-tools/
  cp "$BOLT_BIN_DIR/perf2bolt" bolt-tools/
fi

echo "[INFO] BOLT binary ready in $BOLT_DIR."
echo "[INFO] BOLT build complete."
