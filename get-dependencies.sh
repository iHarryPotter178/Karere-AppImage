#!/usr/bin/env bash
set -euo pipefail

# Install required build tools, GTK4, libadwaita, and blueprint compiler
apt-get update
apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git curl jq ca-certificates \
    libgtk-4-dev libadwaita-1-dev blueprint-compiler \
    libasound2-dev libglib2.0-dev libnss3-dev
