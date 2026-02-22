FROM nixos/nix:latest

# Configurable target architecture for the NixOS ISO
# Supported values: x86_64-linux, aarch64-linux
ARG TARGET_ARCH=x86_64-linux
ENV TARGET_ARCH=${TARGET_ARCH}

# Install sed so our build script can parse and modify the template
RUN nix-env -iA nixpkgs.gnused

# Copy our template and build script into the container
COPY config/unattended-iso.nix /unattended-iso.nix
COPY config/configuration.nix /configuration.nix
COPY build-iso.sh /build-iso.sh

# Ensure the script is executable
RUN chmod +x /build-iso.sh

# Set the entrypoint to our script
ENTRYPOINT ["/build-iso.sh"]