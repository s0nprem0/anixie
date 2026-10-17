{
  imports = [
    ./options.nix
    ./desktop
    ./programs
    ./theme
  ];

  home.username = "son";
  home.homeDirectory = "/home/son";

  home.stateVersion = "26.05";
}
