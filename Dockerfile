FROM nixos/nix:latest

# OpenContainer labels
LABEL org.opencontainers.image.title="NixOS Swarm Node ISO Builder"
LABEL org.opencontainers.image.description="Multi-arch Docker image for building unattended NixOS ISO for Swarm nodes"
LABEL org.opencontainers.image.version="1.2"
LABEL org.opencontainers.image.authors="KilianSen"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.source="https://github.com/KilianSen/nixos-swarm-node/"

# Required to enable Flakes and Nix-command at build-time and runtime
RUN mkdir -p /etc/nix && \
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

# Install gnused to ensure robust script execution
RUN nix-env --option sandbox false -iA nixpkgs.gnused

# Copy our configuration files and build scripts
COPY config/unattended-iso.nix /unattended-iso.nix
COPY config/configuration.nix /configuration.nix
COPY build-iso.sh /build-iso.sh
COPY flake.nix /flake.nix

# Ensure the script is executable
RUN chmod +x /build-iso.sh

# Set the entrypoint to our script
ENTRYPOINT ["/build-iso.sh"]
