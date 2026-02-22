{
  description = "NixOS Swarm Node ISO Builder";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }: 
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      # This allows building with: nix build .#isoImage --argstr system x86_64-linux
      packages = forAllSystems (system: {
        isoImage = (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./config/unattended-iso.nix
            {
              # Inject global configuration.nix
              system.configurationRevision = nixpkgs.lib.mkIf (self ? rev) self.rev;
            }
          ];
        }).config.system.build.isoImage;
      });

      # Default package for the current system
      defaultPackage = forAllSystems (system: self.packages.${system}.isoImage);
    };
}
