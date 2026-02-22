{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Include the configuration file in the live environment's /etc
  environment.etc."nixos-configuration-template.nix".source = ./configuration.nix;

  # Allow root login via SSH (in addition to key-based if provided)
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";

  # SSH Key Injection
  users.users.root.openssh.authorizedKeys.keys = lib.mkIf ("__SSH_KEY__" != "") [
    "__SSH_KEY__"
  ];
  
  # Allow empty root password for local console login (if no SSH key provided)
  users.users.root.initialHashedPassword = lib.mkForce (if "__SSH_KEY__" == "" then "" else "*");

  systemd.services.auto-install = {
    description = "Unattended NixOS Installation";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = with pkgs; [ parted e2fsprogs dosfstools nixos-install-tools utillinux bash coreutils ];

    script = ''
      set -e

      # Runtime variables (injected by build-iso.sh)
      TARGET_DISK="__TARGET_DISK__"
      MANAGER_IP="__MANAGER_IP__"
      SWARM_TOKEN="__SWARM_TOKEN__"
      SSH_KEY="__SSH_KEY__"
      PARTITION_SIZE="__PARTITION_SIZE__" # e.g., "100%", "50GB", etc.

      echo "==> STARTING UNATTENDED INSTALLATION"
      echo "    Target Disk: $TARGET_DISK"
      echo "    Nix Partition Size: $PARTITION_SIZE"

      # Error handling function
      on_error() {
        echo "!!! ERROR DURING INSTALLATION !!!"
        echo "Check the logs above for more details."
        echo "The system will NOT reboot automatically to allow for manual debugging."
        echo "You can SSH into this live environment or use the local console."
        echo "Waiting indefinitely..."
        sleep infinity
      }
      trap 'on_error' ERR

      echo "==> Partitioning $TARGET_DISK..."
      parted -s "$TARGET_DISK" -- mklabel gpt
      parted -s "$TARGET_DISK" -- mkpart ESP fat32 1MiB 512MiB
      parted -s "$TARGET_DISK" -- set 1 esp on
      
      # Handle the partition size: 'full' translates to '100%'
      END_POINT="$PARTITION_SIZE"
      if [ "$END_POINT" = "full" ] || [ -z "$END_POINT" ]; then
        END_POINT="100%"
      fi
      
      echo "==> Creating NixOS partition with size: $END_POINT"
      parted -s "$TARGET_DISK" -- mkpart primary 512MiB "$END_POINT"

      udevadm settle

      echo "==> Formatting partitions..."
      mkfs.fat -F 32 -n boot "''${TARGET_DISK}1"
      mkfs.ext4 -L nixos "''${TARGET_DISK}2"

      echo "==> Mounting filesystems..."
      mount /dev/disk/by-label/nixos /mnt
      mkdir -p /mnt/boot
      mount /dev/disk/by-label/boot /mnt/boot

      echo "==> Generating hardware configuration..."
      nixos-generate-config --root /mnt

      echo "==> Copying static configuration..."
      cp /etc/nixos-configuration-template.nix /mnt/etc/nixos/configuration.nix

      # Add SSH key to the installed system if provided
      if [ -n "$SSH_KEY" ]; then
        echo "==> Injecting SSH authorized keys into installed system..."
        mkdir -p /mnt/root/.ssh
        echo "$SSH_KEY" >> /mnt/root/.ssh/authorized_keys
        chmod 700 /mnt/root/.ssh
        chmod 600 /mnt/root/.ssh/authorized_keys
      fi

      echo "==> Storing Swarm credentials..."
      mkdir -p /mnt/root/swarm-secrets
      echo "$MANAGER_IP" > /mnt/root/swarm-secrets/manager_ip
      echo "$SWARM_TOKEN" > /mnt/root/swarm-secrets/worker_token
      chmod -R 700 /mnt/root/swarm-secrets

      echo "==> Starting NixOS installation..."
      nixos-install --no-root-passwd

      echo "==> INSTALLATION SUCCESSFUL! Rebooting in 10 seconds..."
      sleep 10
      reboot
    '';
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };
}
