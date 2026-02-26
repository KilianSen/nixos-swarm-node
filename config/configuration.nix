{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  services.openssh.enable = true;
  virtualisation.docker.enable = true;
  networking.firewall.enable = true;

  users.users.root.initialPassword = "__ROOT_PASSWORD__";

  networking.firewall.allowedTCPPorts = [ 2377 7946 ];
  networking.firewall.allowedUDPPorts = [ 7946 4789 ];

  systemd.services.docker-swarm-join = {
    description = "Auto-join Docker Swarm";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.docker ];
    script = ''
      SWARM_STATE=$(${pkgs.docker}/bin/docker info --format '{{.Swarm.LocalNodeState}}')
      if [ "$SWARM_STATE" = "active" ]; then exit 0; fi
      if [ -f "/root/swarm-secrets/worker_token" ] && [ -f "/root/swarm-secrets/manager_ip" ]; then
        ${pkgs.docker}/bin/docker swarm join \
          --token "$(cat /root/swarm-secrets/worker_token)" \
          "$(cat /root/swarm-secrets/manager_ip)":2377
      fi
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };

  system.stateVersion = "25.11";
}
