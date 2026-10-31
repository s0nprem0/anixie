{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    ndi-6
  ];
}
