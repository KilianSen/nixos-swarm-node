{ config, pkgs, ... }:
{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>
  ];

  users.users.root.initialHashedPassword = "";

  systemd.services.auto-install = {
    description = "Unattended NixOS Installation";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = with pkgs; [ parted e2fsprogs dosfstools nixos-install-tools utillinux bash ];

    script = ''
      set -e
      TARGET_DISK="__TARGET_DISK__"
      MANAGER_IP="__MANAGER_IP__"
      SWARM_TOKEN="__SWARM_TOKEN__"

      parted -s "$TARGET_DISK" -- mklabel gpt
      parted -s "$TARGET_DISK" -- mkpart ESP fat32 1MiB 512MiB
      parted -s "$TARGET_DISK" -- set 1 esp on
      parted -s "$TARGET_DISK" -- mkpart primary 512MiB 100%

      udevadm settle

      mkfs.fat -F 32 -n boot ''${TARGET_DISK}1
      mkfs.ext4 -L nixos ''${TARGET_DISK}2

      mount /dev/disk/by-label/nixos /mnt
      mkdir -p /mnt/boot
      mount /dev/disk/by-label/boot /mnt/boot

      nixos-generate-config --root /mnt

      cp /configuration.nix /mnt/etc/nixos/configuration.nix

      mkdir -p /mnt/root/swarm-secrets
      echo "$MANAGER_IP" > /mnt/root/swarm-secrets/manager_ip
      echo "$SWARM_TOKEN" > /mnt/root/swarm-secrets/worker_token
      chmod -R 700 /mnt/root/swarm-secrets

      nixos-install --no-root-passwd
      sleep 5
      reboot
    '';
  };
}