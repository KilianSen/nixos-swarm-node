{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Include the configuration file in the live environment's /etc
  environment.etc."nixos-configuration-template.nix".source = ./configuration.nix;

  # Include Docker in the ISO for debugging/manual use
  virtualisation.docker.enable = true;
  environment.systemPackages = with pkgs; [ docker ];

  # Allow root login via SSH (in addition to key-based if provided)
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";

  # SSH Key Injection
  users.users.root.openssh.authorizedKeys.keys = lib.mkIf ("__SSH_KEY__" != "") [
    "__SSH_KEY__"
  ];
  
  # Allow empty root password for local console login (if no SSH key provided)
  users.users.root.initialHashedPassword = lib.mkForce (if "__SSH_KEY__" == "" then "" else "*");

  # Enable flakes in the live environment
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  systemd.services.auto-install = {
    description = "Unattended NixOS Installation";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ 
      parted e2fsprogs dosfstools nixos-install-tools utillinux bash coreutils 
      jq curl kmod iproute2 nix perl
    ];

    script = ''
      set -e

      # Runtime variables (injected by build-iso.sh)
      TARGET_DISK="__TARGET_DISK__"
      MANAGER_IP="__MANAGER_IP__"
      SWARM_TOKEN="__SWARM_TOKEN__"
      SSH_KEY="__SSH_KEY__"
      PARTITION_SIZE="__PARTITION_SIZE__" # e.g., "100%", "50GB", etc.

      echo "============================================"
      echo "==> STARTING UNATTENDED INSTALLATION"
      echo "    Target Disk: $TARGET_DISK"
      echo "    Nix Partition Size: $PARTITION_SIZE"
      echo "============================================"

      # Error handling function
      on_error() {
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!!! ERROR DURING INSTALLATION !!!"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "The system will NOT reboot automatically to allow for manual debugging."
        echo "You can check logs with: journalctl -u auto-install"
        echo "Waiting indefinitely..."
        sleep infinity
      }
      trap 'on_error' ERR

      # Check for UEFI
      if [ ! -d /sys/firmware/efi ]; then
        echo "!!! ERROR: This system was NOT booted via UEFI !!!"
        echo "The current configuration (systemd-boot) requires UEFI."
        echo "Please enable UEFI in BIOS or use GRUB instead."
        exit 1
      fi

      echo "==> Partitioning $TARGET_DISK..."
      # Create fresh GPT partition table
      parted -s "$TARGET_DISK" -- mklabel gpt
      # 1. ESP (EFI System Partition)
      parted -s "$TARGET_DISK" -- mkpart ESP fat32 1MiB 512MiB
      parted -s "$TARGET_DISK" -- set 1 esp on
      
      # Handle the partition size: 'full' translates to '100%'
      END_POINT="$PARTITION_SIZE"
      if [ "$END_POINT" = "full" ] || [ -z "$END_POINT" ]; then
        END_POINT="100%"
      fi
      
      # 2. NixOS Partition
      echo "==> Creating NixOS partition with size: $END_POINT"
      parted -s "$TARGET_DISK" -- mkpart primary 512MiB "$END_POINT"

      # Ensure kernel knows about new partitions
      udevadm settle
      sleep 2
      udevadm settle

      # Determine partition names correctly (handling /dev/nvme0n1 vs /dev/sda)
      if [[ "$TARGET_DISK" == *nvme* ]] || [[ "$TARGET_DISK" == *mmcblk* ]] || [[ "$TARGET_DISK" == *loop* ]]; then
        P1="''${TARGET_DISK}p1"
        P2="''${TARGET_DISK}p2"
      else
        P1="''${TARGET_DISK}1"
        P2="''${TARGET_DISK}2"
      fi

      echo "==> Formatting partitions..."
      echo "    P1 (Boot): $P1"
      echo "    P2 (Root): $P2"
      
      # Verify devices exist before formatting
      if [ ! -b "$P1" ] || [ ! -b "$P2" ]; then
        echo "!!! ERROR: Partition devices $P1 or $P2 not found !!!"
        echo "Current block devices:"
        lsblk
        exit 1
      fi

      mkfs.fat -F 32 -n boot "$P1"
      mkfs.ext4 -L nixos -F "$P2"

      # Force udev to recognize new labels/UUIDs
      udevadm trigger
      udevadm settle

      echo "==> Mounting filesystems..."
      mount "$P2" /mnt
      mkdir -p /mnt/boot
      mount "$P1" /mnt/boot

      echo "==> Generating hardware configuration..."
      nixos-generate-config --root /mnt

      echo "==> Copying static configuration..."
      cp /etc/nixos-configuration-template.nix /mnt/etc/nixos/configuration.nix

      # Add SSH key to the installed system if provided
      if [ -n "$SSH_KEY" ] && [ "$SSH_KEY" != "__SSH_KEY__" ]; then
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
      # Use --no-channel-copy to speed up if needed, but we probably want it
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
