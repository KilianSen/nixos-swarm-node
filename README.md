# NixOS Swarm Node — Unattended ISO Builder

A Docker-based tool that builds a fully automated NixOS installer ISO for Docker Swarm worker nodes. Boot the ISO on any bare-metal machine and it will partition the disk, install NixOS, and join the Swarm — no human interaction required.

---

## Features

- **Modern Nix**: Powered by Nix Flakes and pinned to the stable `24.11` release.
- **Truly Multi-arch**: Build `x86_64-linux` or `aarch64-linux` ISOs on any platform.
- **Secure Access**: Inject your SSH public key during the build for immediate, secure access.
- **Custom Partitioning**: Choose how much disk space to allocate for the NixOS partition.
- **Robust Error Handling**: If installation fails, the installer pauses for manual debugging instead of rebooting into an empty system.

---

## Prerequisites

| Tool | Version |
|---|---|
| Docker | 20.10 + |
| QEMU / `binfmt` support | required for cross-arch builds |

---

## Generating an ISO

Pull the multi-arch pre-built image and run it with your Swarm credentials.

```bash
docker run --rm \
  -v "$(pwd)/iso-output:/out" \
  ghcr.io/kiliansen/nixos-swarm-node:latest \
  <MANAGER_IP> <SWARM_TOKEN> [TARGET_DISK] [ARCH] [SSH_KEY] [PART_SIZE]
```

### Arguments

| Argument | Required | Default | Description |
|---|---|---|---|
| `MANAGER_IP` | ✅ | — | IP of the Docker Swarm manager |
| `SWARM_TOKEN` | ✅ | — | Worker join token (`docker swarm join-token worker -q`) |
| `TARGET_DISK` | ❌ | `/dev/sda` | Block device to install NixOS onto |
| `ARCH` | ❌ | *host* | Target arch (`x86_64-linux` or `aarch64-linux`) |
| `SSH_KEY` | ❌ | — | Public SSH key (e.g. `"ssh-ed25519 AAA..."`) |
| `PART_SIZE` | ❌ | `full` | Partition size (e.g. `50GB`, `20%`, or `full`) |

The finished ISO will appear in `./iso-output/`.

---

## Examples

### Secure Build (with SSH Key)
Recommended for secure, passwordless access:
```bash
docker run --rm -v "$(pwd)/out:/out" ghcr.io/kiliansen/nixos-swarm-node:latest \
  192.168.1.10 SWMTKN-1-abc-123 /dev/sda x86_64-linux "$(cat ~/.ssh/id_ed25519.pub)"
```

### Custom Disk Sizing
To build an ISO that only uses 50GB of a larger disk (leaving the rest unallocated):
```bash
docker run --rm -v "$(pwd)/out:/out" ghcr.io/kiliansen/nixos-swarm-node:latest \
  1.2.3.4 token_here /dev/sda x86_64-linux "" 50GB
```

---

## Error Handling & Debugging

If the installation process encounters an error, it will:
1. Log the error to the console and system journal.
2. Pause indefinitely (`sleep infinity`) to prevent an endless reboot loop.
3. Allow you to inspect the system via the local console or SSH (if an SSH key was provided).

To check logs manually on the live system:
```bash
journalctl -u auto-install.service
```

---

## CI / CD — GitHub Actions

The workflow at `.github/workflows/release.yml` builds and pushes the multi-arch image to GHCR on every push to `main`. It uses the `flake.nix` for consistent, pinned builds.

---

## License

MIT
