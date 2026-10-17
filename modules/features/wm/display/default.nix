{ pkgs, ... }:

{
  # Stand-in for the display settings GNOME used to provide: resolution,
  # scale, refresh rate and output switching from the terminal.
  home.packages = [ pkgs.wlr-randr ];
}
