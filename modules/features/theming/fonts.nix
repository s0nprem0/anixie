{ pkgs, ... }:

{
  home.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.gohufont
  ];

  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    TERMINAL_FONT = "JetBrains Mono";
  };
}
