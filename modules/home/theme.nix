{ config, ... }:

{
  home.file.".config/nix-dots/theme.json".text =
    builtins.toJSON {
      inherit (config.myDots.theme) name colors;
    };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    MOZ_ENABLE_WAYLAND = "1";
  };
}
