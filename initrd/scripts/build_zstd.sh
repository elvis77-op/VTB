#!/bin/bash

set -e

ZSTD_VERSION="1.5.5"
ZSTD_URL="https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"

echo "Building static zstd..."

wget "$ZSTD_URL"
tar -xzf "zstd-${ZSTD_VERSION}.tar.gz"
cd "zstd-${ZSTD_VERSION}"

make -j$(nproc) \
    CFLAGS="-static -Os -DNDEBUG" \
    LDFLAGS="-static" \
    zstd

echo "Verifying static binary..."
file programs/zstd
ldd programs/zstd 2>&1 | grep -q "not a dynamic executable" && echo "Static binary confirmed"

mkdir -p ../rootfs/bin
cp programs/zstd ../rootfs/bin/
chmod +x ../rootfs/bin/zstd

cd ..
rm -rf zstd-${ZSTD_VERSION} zstd-${ZSTD_VERSION}.tar.gz

echo "zstd installed"