#!/bin/sh
set -eu

ARCH="$(uname -m)"

VERSION="$(
    sed -n 's/^version = "\(.*\)"/\1/p' \
        /tmp/karere/Cargo.toml |
    head -n1
)"

export ARCH
export VERSION

export OUTPATH="$PWD/dist"

export ICON="/usr/share/icons/hicolor/256x256/apps/io.github.tobagin.karere.png"
export DESKTOP="/usr/share/applications/io.github.tobagin.karere.desktop"

echo "==> Karere version: $VERSION"
echo "==> Architecture: $ARCH"

echo "==> Deploying Karere with quick-sharun..."

quick-sharun \
    /usr/bin/karere \
    /usr/lib/cef

echo "==> Creating AppImage..."

quick-sharun --make-appimage

echo "==> Testing AppImage..."

quick-sharun --test ./dist/*.AppImage

echo
echo "============================================================"
echo "AppImage successfully created:"
echo "============================================================"
ls -lh ./dist/*.AppImage
