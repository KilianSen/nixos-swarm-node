# NixOS Swarm Node — Unattended ISO Builder

A Docker-based tool that builds a fully automated NixOS installer ISO for Docker Swarm worker nodes. Boot the ISO on any bare-metal machine and it will partition the disk, install NixOS, and join the Swarm — no human interaction required.

---

## How it works

```
Docker container (nixos/nix)
  └─ build-iso.sh          ← injects runtime args into the Nix template
       └─ unattended-iso.nix  ← NixOS config with a systemd auto-install service
            └─ configuration.nix  ← base NixOS system config (Docker, networking, …)
```

On first boot the generated ISO runs a `systemd` service that:
1. Partitions the target disk (GPT, EFI + ext4)
2. Formats and mounts the partitions
3. Installs NixOS with `nixos-install`
4. Writes Swarm credentials to `/root/swarm-secrets/`
5. Reboots into the freshly installed system, which auto-joins the Swarm

---

## Prerequisites

| Tool | Version |
|---|---|
| Docker | 20.10 + |
| QEMU / `binfmt` support | only for cross-arch builds |

---

## Building the image locally

```bash
# Default: x86_64-linux
docker build -t nixos-swarm-node .

# Explicit architecture
docker build --build-arg TARGET_ARCH=aarch64-linux -t nixos-swarm-node:arm64 .
```

Supported `TARGET_ARCH` values:

| Value | Description |
|---|---|
| `x86_64-linux` | Standard 64-bit PC (default) |
| `aarch64-linux` | ARM 64-bit (Raspberry Pi 4/5, Apple Silicon VMs, …) |

---

## Generating an ISO

```bash
docker run --rm \
  -v "$(pwd)/iso-output:/out" \
  ghcr.io/kiliansen/nixos-swarm-node \
  <MANAGER_IP> <SWARM_TOKEN> [TARGET_DISK]
```

| Argument | Required | Default | Description |
|---|---|---|---|
| `MANAGER_IP` | ✅ | — | IP of the Docker Swarm manager |
| `SWARM_TOKEN` | ✅ | — | Worker join token (`docker swarm join-token worker -q`) |
| `TARGET_DISK` | ❌ | `/dev/sda` | Block device to install NixOS onto |

The finished ISO will appear in `./iso-output/`.

> **Warning:** The installer wipes `TARGET_DISK` completely. Double-check the device name before booting.

---

## Using the pre-built image from GHCR

Every push to `main` automatically builds and publishes images to the GitHub Container Registry.

```bash
# x86_64
docker pull ghcr.io/kiliansen/nixos-swarm-node:latest-amd64

# aarch64
docker pull ghcr.io/kiliansen/nixos-swarm-node:latest-arm64
```

Versioned tags follow the pattern `YYYY.MM.DD-<run_number>` (e.g. `2026.02.22-5`).

---

## CI / CD — GitHub Actions

The workflow at `.github/workflows/release.yml` runs on every push to `main`:

```
push → main
  ├─ [tag]     Create & push a CalVer git tag (YYYY.MM.DD-<run_number>)
  ├─ [build]   Build Docker images in parallel
  │             ├─ x86_64-linux  → ghcr.io/…:TAG-amd64
  │             └─ aarch64-linux → ghcr.io/…:TAG-arm64
  └─ [release] Create a GitHub Release with pull instructions
```

---

## Project structure

```
.
├── Dockerfile            # Builder image (nixos/nix base, configurable arch)
├── build-iso.sh          # Entrypoint: injects args, calls nix-build
├── unattended-iso.nix    # NixOS installer config template
├── configuration.nix     # Base NixOS system configuration
├── iso-output/           # Default local output directory (git-ignored)
└── .github/
    └── workflows/
        └── release.yml   # Tag → Build → Release pipeline
```

---

## License

MIT
