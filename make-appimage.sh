#!/usr/bin/env bash
set -eo pipefail

echo "==> 1. Determining the latest stable Karere application tag..."
# Uses git ls-remote to find tags matching ONLY vX.Y.Z, entirely bypassing /releases/latest and cef-* tags
KARERE_TAG=$(git ls-remote --tags https://github.com/tobagin/karere | awk '{print $2}' | grep -oE 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's|refs/tags/||' | sort -V | tail -n1)

if [ -z "$KARERE_TAG" ]; then
    echo "ERROR: Failed to detect a valid Karere version tag!"
    exit 1
fi

KARERE_VERSION=${KARERE_TAG#v}
echo "==> Detected latest stable application version: $KARERE_TAG ($KARERE_VERSION)"

# Check if we already released this exact version in this repo
if gh release view "$KARERE_TAG" &>/dev/null; then
    echo "==> Release $KARERE_TAG already exists in our repository."
    # Set flag to skip GH Release step at the end, but continue building the artifact
    echo "NEW_RELEASE=false" >> "$GITHUB_ENV"
else
    echo "NEW_RELEASE=true" >> "$GITHUB_ENV"
fi
echo "KARERE_TAG=$KARERE_TAG" >> "$GITHUB_ENV"
echo "KARERE_VERSION=$KARERE_VERSION" >> "$GITHUB_ENV"

echo "==> 2. Checking out Karere..."
git clone --branch "$KARERE_TAG" --depth 1 https://github.com/tobagin/karere.git build-karere
cd build-karere

echo "==> 3. Verifying Cargo.toml version..."
CARGO_VERSION=$(grep -m 1 '^version = ' Cargo.toml | cut -d '"' -f 2)
if [ "$KARERE_VERSION" != "$CARGO_VERSION" ]; then
    echo "ERROR: Version mismatch! Git tag is $KARERE_VERSION but Cargo.toml specifies $CARGO_VERSION."
    exit 1
fi
echo "==> Version match verified ($CARGO_VERSION)."

echo "==> 4. Detecting required CEF version and checksum from source..."
# Scrape the required CEF tag exact string from Karere's own source files (often in build scripts/workflows)
CEF_EXPECTED_TAG=$(grep -RhoE 'cef-[0-9]+\.[0-9]+\.[0-9]+-proprietary-codecs' . | sort -u | head -n1 || true)

if [ -z "$CEF_EXPECTED_TAG" ]; then
    echo "WARNING: Could not automatically grep the CEF tag in the source code."
    echo "Falling back to querying the Karere releases API for the latest CEF tag..."
    CEF_EXPECTED_TAG=$(gh api repos/tobagin/karere/releases --jq '.[].tag_name' | grep -E '^cef-' | sort -V | tail -n1)
fi
echo "==> Using CEF release tag: $CEF_EXPECTED_TAG"

# Determine exact filenames from the matched CEF release
CEF_ASSET=$(gh release view "$CEF_EXPECTED_TAG" --repo tobagin/karere --json assets --jq '.assets[].name' | grep -iE 'linux64.*\.tar\.(bz2|gz|xz)$' | head -n1)
if [ -z "$CEF_ASSET" ]; then
    echo "ERROR: Could not find a linux64 CEF tarball in release $CEF_EXPECTED_TAG"
    exit 1
fi

echo "==> Downloading CEF archive ($CEF_ASSET)..."
gh release download "$CEF_EXPECTED_TAG" --repo tobagin/karere --pattern "$CEF_ASSET"

SHA_ASSET=$(gh release view "$CEF_EXPECTED_TAG" --repo tobagin/karere --json assets --jq '.assets[].name' | grep -iE '(\.sha256|sha256sum)' | head -n1 || true)
if [ -n "$SHA_ASSET" ]; then
    echo "==> Validating CEF SHA256 checksum against official release hashes..."
    gh release download "$CEF_EXPECTED_TAG" --repo tobagin/karere --pattern "$SHA_ASSET"
    grep "$CEF_ASSET" "$SHA_ASSET" | sha256sum --check -
else
    echo "WARNING: No SHA256 checksum file found in upstream release. Manual checksum:"
    sha256sum "$CEF_ASSET"
fi

echo "==> Extracting CEF..."
mkdir -p cef_extract
tar -xf "$CEF_ASSET" -C cef_extract --strip-components=1

# Expose CEF paths for Cargo (standard for rust-cef build scripts)
export CEF_ROOT="$(pwd)/cef_extract"
export CEF_PATH="$(pwd)/cef_extract"

echo "==> 5. Building Karere application..."
cargo build --release

echo "==> 6. Preparing AppDir..."
cd ..
mkdir -p AppDir/usr/bin
mkdir -p AppDir/usr/share/applications
mkdir -p AppDir/usr/share/icons/hicolor/256x256/apps

# Binary
cp build-karere/target/release/karere AppDir/usr/bin/

# CEF Libraries and Resources (Required alongside binary)
cp -a build-karere/cef_extract/Release/* AppDir/usr/bin/ 2>/dev/null || true
cp -a build-karere/cef_extract/Resources/* AppDir/usr/bin/ 2>/dev/null || true

# Desktop integration
if [ -f build-karere/assets/karere.desktop ]; then
    cp build-karere/assets/karere.desktop AppDir/usr/share/applications/
else
    cat > AppDir/usr/share/applications/karere.desktop <<EOF
[Desktop Entry]
Name=Karere
Exec=karere %U
Icon=karere
Type=Application
Categories=Network;WebBrowser;
Terminal=false
EOF
fi

if [ -f build-karere/assets/icon.png ]; then
    cp build-karere/assets/icon.png AppDir/usr/share/icons/hicolor/256x256/apps/karere.png
    cp build-karere/assets/icon.png AppDir/karere.png
else
    # Fallback to an empty icon if missing to prevent AppImage tool failures
    touch AppDir/karere.png
fi

echo "==> 7. Creating AppImage with quick-sharun..."
wget -q https://github.com/pkgforge-dev/quick-sharun/releases/latest/download/quick-sharun-x86_64
chmod +x quick-sharun-x86_64

mkdir -p out
./quick-sharun-x86_64 \
    --appdir AppDir \
    --exec usr/bin/karere \
    --out "out/Karere-${KARERE_VERSION}-x86_64.AppImage"

echo "==> 8. Testing AppImage extractability..."
cd out
chmod +x *.AppImage
./*.AppImage --appimage-extract
if [ -x squashfs-root/AppRun ]; then
    echo "==> AppImage is valid and extractable."
else
    echo "ERROR: Generated AppImage failed integrity check (no AppRun found)."
    exit 1
fi
rm -rf squashfs-root

echo "==> SUCCESS: Build complete!"
