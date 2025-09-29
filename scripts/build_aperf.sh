#!/bin/bash
# Build script for Aperf (download binary release)
set -e

APERF_VERSION="v0.1.15-alpha"
# APERF_TAR="aperf-${APERF_VERSION}-aarch64.tar.gz"
# APERF_URL="https://github.com/aws/aperf/releases/download/${APERF_VERSION}/${APERF_TAR}"
ARCH=$(uname -m)
case "$ARCH" in
  aarch64|arm64) AP_ARCH="aarch64" ;;
  x86_64|amd64)  AP_ARCH="x86_64" ;;
  *) echo "[ERROR] Unsupported architecture: $ARCH"; exit 1 ;;
esac

APERF_TAR="aperf-${APERF_VERSION}-${AP_ARCH}.tar.gz"
APERF_URL="https://github.com/aws/aperf/releases/download/${APERF_VERSION}/${APERF_TAR}"
APERF_DIR="aperf-bin"

if [ ! -f "$APERF_TAR" ]; then
  echo "[INFO] Downloading Aperf binary release..."
  wget -q "$APERF_URL"
fi

if [ -d "$APERF_DIR" ]; then
  rm -rf "$APERF_DIR"
fi
mkdir "$APERF_DIR"
tar xzf "$APERF_TAR" -C "$APERF_DIR"

# Find and copy the extracted binary into the aperf directory
APERF_EXTRACTED=$(find aperf-bin -type f -name 'aperf' | head -n1)
if [ -n "$APERF_EXTRACTED" ]; then
  mkdir -p aperf
  cp "$APERF_EXTRACTED" aperf/aperf
  echo "[INFO] Aperf binary staged in aperf/aperf."
else
  echo "[ERROR] Aperf binary not found after extraction. Build failed."
  exit 1
fi

echo "[INFO] Aperf build complete."
