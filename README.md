# NixOS Swarm Node — Unattended ISO Builder

A Docker-based tool that builds a fully automated NixOS installer ISO for Docker Swarm worker nodes. Boot the ISO on any bare-metal machine or VM, and it will partition the disk, install NixOS, and join the Swarm — no human interaction required.

---

## Features

- **Modern Nix**: Powered by Nix Flakes and pinned to the stable `24.11` release.
- **Truly Multi-arch**: Build `x86_64-linux` or `aarch64-linux` ISOs.
- **Secure Access**: Use SSH public keys or set an initial root password.
- **Robust Partitioning**: Supports NVMe (`/dev/nvme0n1`), SCSI (`/dev/sda`), and VirtIO (`/dev/vda`).
- **Debugging Tools**: The live ISO environment includes `docker`, `vim`, `git`, and `nix` for manual troubleshooting.
- **Fail-Safe**: If installation fails, the installer pauses for manual debugging instead of rebooting into an empty system.

---

## Prerequisites

| Tool | Version |
|---|---|
| Docker | 20.10 + |
| QEMU / `binfmt` support | required for cross-arch builds |

---

## Generating an ISO

Build the builder image locally, then run it using environment variables to configure your node.

```bash
# 1. Build the builder
docker build -t nixos-iso-builder .

# 2. Generate the ISO
docker run --rm \
  -v "$(pwd)/out:/out" \
  -v nix-cache:/nix \
  -e MANAGER_IP="192.168.1.10" \
  -e SWARM_TOKEN="SWMTKN-1-xxxx..." \
  -e ROOT_PASSWORD="my-secret-password" \
  nixos-iso-builder
```

### Configuration (Environment Variables)

| Variable | Required | Default | Description |
|---|---|---|---|
| `MANAGER_IP` | ✅ | — | IP of the Docker Swarm manager |
| `SWARM_TOKEN` | ✅ | — | Worker join token |
| `ROOT_PASSWORD` | ❌ | — | Initial password for the root user |
| `SSH_KEY` | ❌ | — | Public SSH key (e.g. `"ssh-ed25519 AAA..."`) |
| `TARGET_DISK` | ❌ | `/dev/sda` | Block device to install NixOS onto |
| `ARCH` | ❌ | *host* | Target arch (`x86_64-linux` or `aarch64-linux`) |
| `PARTITION_SIZE` | ❌ | `full` | Nix partition size (e.g. `50GB`, `20%`, or `full`) |

The finished ISO will appear in your local `./out/` directory.

---

## Performance Tip: Use a Nix Cache
Building a NixOS ISO involves downloading several GBs of data. To make subsequent builds take seconds instead of minutes, use a Docker volume to persist the Nix store:

```bash
docker volume create nix-cache
docker run --rm -v "$(pwd)/out:/out" -v nix-cache:/nix ...
```

---

## Proxmox Setup

To ensure the automated installation and subsequent boots work correctly, use these VM settings:

1.  **BIOS**: Must be **OVMF (UEFI)**. The default `systemd-boot` configuration requires UEFI.
2.  **Machine**: Use `q35`.
3.  **Disks**: Use **SCSI** for the best compatibility with the default `/dev/sda` target. 
    *   If you use *VirtIO Block*, set `-e TARGET_DISK="/dev/vda"`.
4.  **Network**: Ensure the bridge has access to your `MANAGER_IP`.

---

## Error Handling & Debugging

If the installation process encounters an error (e.g., disk not found or network down), it will:
1. Print a clear error message to the console.
2. Pause indefinitely to allow you to investigate.
3. Allow you to login via the Proxmox console (username `root`, no password).

**Useful commands in the live environment:**
- `journalctl -u auto-install -f`: Watch the installation logs.
- `lsblk`: See detected disks and partition names.
- `docker ps`: Verify the Docker engine is running in the live environment.

---

## License

MIT
