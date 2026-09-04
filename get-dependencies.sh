#!/bin/sh
set -eu

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|aarch64)
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "==> Installing build dependencies..."

pacman -Syu --noconfirm --needed \
    base-devel \
    git \
    curl \
    unzip \
    python \
    meson \
    ninja \
    rust \
    pkgconf \
    gettext \
    blueprint-compiler \
    gtk4 \
    libadwaita \
    gdk-pixbuf2 \
    libepoxy \
    libx11 \
    patchelf \
    strace \
    xorg-server-xvfb

echo "==> Installing common debloated packages..."

get-debloated-pkgs --add-common --prefer-nano

echo "==> Finding latest Karere release..."

RELEASE_JSON="$(curl -LfsS \
    https://api.github.com/repos/tobagin/karere/releases/latest)"

KARERE_TAG="$(
    printf '%s\n' "$RELEASE_JSON" |
    python3 -c '
import json, sys
print(json.load(sys.stdin)["tag_name"])
'
)"

echo "==> Latest Karere release: $KARERE_TAG"

rm -rf /tmp/karere
git clone --depth=1 --branch "$KARERE_TAG" \
    https://github.com/tobagin/karere.git \
    /tmp/karere

cd /tmp/karere

echo "==> Reading CEF package information from Karere..."

CEF_INFO="$(
python3 - "$ARCH" <<'PY'
import re
import sys

arch = sys.argv[1]

with open("packaging/io.github.tobagin.karere.yml", "r", encoding="utf-8") as f:
    text = f.read()

pattern = (
    r'- type: archive\s+'
    r'only-arches: \[' + re.escape(arch) + r'\]\s+'
    r'url:\s*(\S+)\s+'
    r'sha256:\s*([0-9a-fA-F]{64})'
)

m = re.search(pattern, text)

if not m:
    raise SystemExit(
        f"Could not find CEF archive for architecture {arch}"
    )

print(m.group(1))
print(m.group(2))
PY
)"

CEF_URL="$(printf '%s\n' "$CEF_INFO" | sed -n '1p')"
CEF_SHA256="$(printf '%s\n' "$CEF_INFO" | sed -n '2p')"

echo "==> CEF URL:"
echo "$CEF_URL"

echo "==> CEF SHA256:"
echo "$CEF_SHA256"

echo "==> Downloading CEF..."

rm -rf /tmp/karere-cef
mkdir -p /tmp/karere-cef

curl -LfsS --retry 3 \
    "$CEF_URL" \
    -o /tmp/karere-cef/cef.zip

echo "$CEF_SHA256  /tmp/karere-cef/cef.zip" |
    sha256sum -c -

echo "==> Extracting CEF..."

unzip -q /tmp/karere-cef/cef.zip \
    -d /tmp/karere-cef

CEF_DIR="$(
    find /tmp/karere-cef \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name 'cef_binary_*' |
    head -n1
)"

if [ -z "$CEF_DIR" ]; then
    echo "ERROR: Could not locate extracted CEF directory."
    exit 1
fi

echo "==> Installing CEF..."

rm -rf /usr/lib/cef
mkdir -p /usr/lib/cef

cp -a "$CEF_DIR/include" /usr/lib/cef/
cp -a "$CEF_DIR/libcef_dll" /usr/lib/cef/
cp -a "$CEF_DIR/cmake" /usr/lib/cef/
cp -a "$CEF_DIR/CMakeLists.txt" /usr/lib/cef/
cp -a "$CEF_DIR/Release/." /usr/lib/cef/
cp -a "$CEF_DIR/Resources/." /usr/lib/cef/

chmod +x /usr/lib/cef/chrome-sandbox 2>/dev/null || true

echo "==> Building Karere..."

export CEF_PATH=/usr/lib/cef

meson setup build \
    --prefix=/usr \
    --buildtype=release

meson compile -C build

echo "==> Installing Karere..."

meson install -C build

echo "==> Karere installation complete."

echo "==> Installed binary:"
ls -lh /usr/bin/karere

echo "==> Installed CEF:"
ls -lh /usr/lib/cef/libcef.so

echo "==> Karere version:"
sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -n1
