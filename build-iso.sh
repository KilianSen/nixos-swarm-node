#!/bin/sh
set -e

# Configuration via environment variables with defaults
MANAGER_IP="${MANAGER_IP}"
SWARM_TOKEN="${SWARM_TOKEN}"
TARGET_DISK="${TARGET_DISK:-/dev/sda}"
ARCH="${ARCH:-$(nix-instantiate --eval -E 'builtins.currentSystem' | tr -d '"' 2>/dev/null || echo "x86_64-linux")}"
SSH_KEY="${SSH_KEY}"
PARTITION_SIZE="${PARTITION_SIZE:-full}"
ROOT_PASSWORD="${ROOT_PASSWORD}"
HOSTNAME="${HOSTNAME:-nixos}"

if [ -z "$MANAGER_IP" ] || [ -z "$SWARM_TOKEN" ]; then
  echo "Error: Missing required environment variables."
  echo "Usage: docker run -e MANAGER_IP=... -e SWARM_TOKEN=... [OPTIONS] ..."
  echo ""
  echo "Options (Environment Variables):"
  echo "  MANAGER_IP       (Required) IP of the Swarm Manager"
  echo "  SWARM_TOKEN      (Required) Docker Swarm Join Token"
  echo "  TARGET_DISK      (Default: /dev/sda) Block device for installation"
  echo "  ARCH             (Default: host arch) x86_64-linux or aarch64-linux"
  echo "  SSH_KEY          (Optional) Public SSH key for root access"
  echo "  PARTITION_SIZE   (Default: full) Size for the Nix partition (e.g. 50GB, 20%)"
  echo "  ROOT_PASSWORD    (Optional) Initial root password for the installed system"
  echo "  HOSTNAME         (Default: nixos) Hostname for the installed system"
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
sed -i "s/__HOSTNAME__/$HOSTNAME/g" $TEMP_CONFIG_DIR/configuration.nix
sed -i "s/__HOSTNAME__/$HOSTNAME/g" $TEMP_CONFIG_DIR/unattended-iso.nix

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
