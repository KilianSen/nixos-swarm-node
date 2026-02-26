#!/bin/sh
set -e

MANAGER_IP=$1
SWARM_TOKEN=$2
TARGET_DISK=${3:-/dev/sda}
ARCH=${4:-$(nix-instantiate --eval -E 'builtins.currentSystem' | tr -d '"' 2>/dev/null || echo "x86_64-linux")}
SSH_KEY=$5
PARTITION_SIZE=${6:-full}
ROOT_PASSWORD=$7

if [ -z "$MANAGER_IP" ] || [ -z "$SWARM_TOKEN" ]; then
  echo "Error: Missing arguments."
  echo "Usage: docker run ... <MANAGER_IP> <SWARM_TOKEN> [TARGET_DISK] [ARCH] [SSH_KEY] [PARTITION_SIZE] [ROOT_PASSWORD]"
  echo ""
  echo "Options:"
  echo "  TARGET_DISK: Block device for installation (default: /dev/sda)"
  echo "  ARCH: x86_64-linux or aarch64-linux (default: host arch)"
  echo "  SSH_KEY: Public SSH key for root access (e.g. \"ssh-ed25519 ...\")"
  echo "  PARTITION_SIZE: Size for the Nix partition (default: full (100%), or e.g. 50GB, 20%)"
  echo "  ROOT_PASSWORD: Initial password for the root user on the installed system"
  exit 1
fi

echo "==> Target architecture: $ARCH"
echo "==> Nix Partition Size: $PARTITION_SIZE"

# Enable experimental features for Flakes
export NIX_CONFIG="experimental-features = nix-command flakes"

# Enable cross-architecture if needed
HOST_ARCH=$(nix-instantiate --eval -E 'builtins.currentSystem' | tr -d '"' 2>/dev/null)
if [ "$ARCH" != "$HOST_ARCH" ]; then
  echo "==> Enabling extra-platforms for $ARCH..."
  mkdir -p /etc/nix
  echo "extra-platforms = x86_64-linux aarch64-linux" >> /etc/nix/nix.conf
fi

echo "==> Preparing build configuration..."
# Inject variables into the template
# We use a temporary directory to build a clean set of config files
TEMP_CONFIG_DIR=$(mktemp -d)
cp /unattended-iso.nix $TEMP_CONFIG_DIR/unattended-iso.nix
cp /configuration.nix $TEMP_CONFIG_DIR/configuration.nix
cp /flake.nix $TEMP_CONFIG_DIR/flake.nix

sed -i "s/__MANAGER_IP__/$MANAGER_IP/g" $TEMP_CONFIG_DIR/unattended-iso.nix
sed -i "s/__SWARM_TOKEN__/$SWARM_TOKEN/g" $TEMP_CONFIG_DIR/unattended-iso.nix
sed -i "s|__TARGET_DISK__|$TARGET_DISK|g" $TEMP_CONFIG_DIR/unattended-iso.nix
sed -i "s|__SSH_KEY__|$SSH_KEY|g" $TEMP_CONFIG_DIR/unattended-iso.nix
sed -i "s|__PARTITION_SIZE__|$PARTITION_SIZE|g" $TEMP_CONFIG_DIR/unattended-iso.nix
sed -i "s|__ROOT_PASSWORD__|$ROOT_PASSWORD|g" $TEMP_CONFIG_DIR/configuration.nix

# Fix path in flake.nix to point to local files in the temp dir
sed -i 's|./config/unattended-iso.nix|./unattended-iso.nix|' $TEMP_CONFIG_DIR/flake.nix

echo "==> Building NixOS ISO using Flakes (this may take some time)..."
cd $TEMP_CONFIG_DIR
nix build .#packages."$ARCH".isoImage \
  --option sandbox false \
  --out-link result

echo "==> Copying ISO to /out..."
mkdir -p /out
# The ISO name often contains the architecture and version
cp result/iso/*.iso /out/

echo "==> Success! ISO ready in your output directory."
# Cleanup
rm -rf $TEMP_CONFIG_DIR
