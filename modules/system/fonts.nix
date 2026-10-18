{ pkgs, ... }:

{
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.gohufont
    nerd-fonts.symbols-only
  ];
}
