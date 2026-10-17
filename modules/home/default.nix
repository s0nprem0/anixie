{
  imports = [
    ./options.nix
    ./desktop
    ./programs
    ./theme
    ./desktop-tools.nix
  ];

  home.username = "son";
  home.homeDirectory = "/home/son";

  home.stateVersion = "26.05";
}
