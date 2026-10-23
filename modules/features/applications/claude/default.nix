{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.claude;
in
{
  options.anixie.applications.claude.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install Claude Code and register its URL handler.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.claude-code ];

    # Claude Code writes its own handler for claude-cli:// links into
    # ~/.local/share/applications and registers it in mimeapps.list. Home Manager
    # owns that file, so the registration would not stick; the desktop entry
    # itself is left to Claude Code, which rewrites it when it updates.
    xdg.mimeApps = {
      enable = true;
      defaultApplications."x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };
  };
}
