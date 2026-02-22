#!/bin/sh
set -e

MANAGER_IP=$1
SWARM_TOKEN=$2
TARGET_DISK=${3:-/dev/sda}
# Architecture: prefer env var (set via Docker ARG), fallback to 4th arg, then default
ARCH=${TARGET_ARCH:-${4:-x86_64-linux}}

if [ -z "$MANAGER_IP" ] || [ -z "$SWARM_TOKEN" ]; then
  echo "Error: Missing arguments."
  echo "Usage: docker run ... <MANAGER_IP> <SWARM_TOKEN> [TARGET_DISK] [ARCH]"
  echo "       or set TARGET_ARCH env variable / Docker build-arg"
  echo "       Supported architectures: x86_64-linux, aarch64-linux"
  exit 1
fi

echo "==> Preparing NixOS configuration (arch: $ARCH)..."
# Inject variables into the template
sed -i "s/__MANAGER_IP__/$MANAGER_IP/g" /unattended-iso.nix
sed -i "s/__SWARM_TOKEN__/$SWARM_TOKEN/g" /unattended-iso.nix
sed -i "s|__TARGET_DISK__|$TARGET_DISK|g" /unattended-iso.nix

echo "==> Building NixOS ISO for $ARCH (This will download ~2GB of dependencies)..."
nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage \
  -I nixos-config=/unattended-iso.nix \
  --argstr system "$ARCH"

echo "==> Copying ISO to /out..."
cp result/iso/*.iso /out/
echo "==> Done! You can find your ISO in your mapped output directory."