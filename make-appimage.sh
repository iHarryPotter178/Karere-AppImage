#!/usr/bin/env bash
set -euo pipefail

# 1. Find latest pure application tag (strictly filtering out cef-* and webkitgtk-* tags)
KARERE_TAG=$(git ls-remote --tags https://github.com/tobagin/karere.git | awk '{print $2}' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)
KARERE_VER="${KARERE_TAG#v}"

# 2. Checkout source and verify Cargo.toml matches the tag
git clone --depth 1 --branch "$KARERE_TAG" https://github.com/tobagin/karere.git source
cd source

CARGO_VER=$(grep -m1 '^version = ' Cargo.toml | cut -d'"' -f2)
if [[ "$KARERE_VER" != "$CARGO_VER" ]]; then
    echo "ERROR: Git tag ($KARERE_VER) does not match Cargo.toml ($CARGO_VER)!" >&2
    exit 1
fi

# 3. Download matching CEF runtime asset from upstream releases
CEF_TAG=$(gh api repos/tobagin/karere/releases --jq '.[].tag_name' | grep '^cef-' | sort -V | tail -n1)
gh release download "$CEF_TAG" --repo tobagin/karere --pattern "*linux64*.tar.*" --dir /tmp/cef
mkdir -p /opt/cef
tar -xf /tmp/cef/* -C /opt/cef --strip-components=1

# 4. Build Karere release binary
export CEF_PATH="/opt/cef"
export CEF_ROOT="/opt/cef"
cargo build --release

# 5. Populate AppDir
cd ..
mkdir -p AppDir/usr/bin AppDir/usr/share/applications AppDir/usr/share/icons/hicolor/256x256/apps
cp source/target/release/karere AppDir/usr/bin/
cp -a /opt/cef/Release/* /opt/cef/Resources/* AppDir/usr/bin/ 2>/dev/null || true
cp source/assets/karere.desktop AppDir/usr/share/applications/ 2>/dev/null || true
cp source/assets/icon.png AppDir/usr/share/icons/hicolor/256x256/apps/karere.png AppDir/karere.png 2>/dev/null || true

# 6. Bundle into AppImage using quick-sharun
curl -sL https://github.com/pkgforge-dev/quick-sharun/releases/latest/download/quick-sharun-x86_64 -o quick-sharun
chmod +x quick-sharun
./quick-sharun --appdir AppDir --exec usr/bin/karere --out "Karere-${KARERE_VER}-x86_64.AppImage"
