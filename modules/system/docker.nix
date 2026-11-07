{ pkgs, ... }:

{
  # Docker Engine (dockerd) + CLI. The corporate-standard replacement for
  # Podman's dockerCompat shim: `docker` on PATH is now the real Docker CLI
  # talking to dockerd on /var/run/docker.sock. The nixpkgs `docker` package
  # wraps the CLI with DOCKER_CLI_PLUGIN_DIRS pointing at the docker-compose
  # and docker-buildx plugins, so `docker compose` and `docker buildx` work
  # out of the box; the standalone binaries are added too for the legacy
  # `docker-compose` / `docker-buildx` spellings.
  virtualisation.docker = {
    enable = true;

    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  environment.systemPackages = with pkgs; [
    docker-compose
    docker-buildx
  ];
}
