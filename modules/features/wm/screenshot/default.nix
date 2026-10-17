{ ... }:

{
  # swappy handles the area capture bind in features/wm/hyprland/keybinds.nix.
  # Fullscreen capture stays on grim, because swappy 1.8 has no headless mode
  # (its whole CLI is just -f and -o) and always opens the selection overlay.
  programs.swappy = {
    enable = true;

    settings.Default = {
      # Matches where the grim bind writes, so both capture routes end up in
      # the same place. save_dir and save_filename_format are the key names
      # present in the swappy 1.8 binary.
      save_dir = "$HOME/Pictures/Screenshots";
      save_filename_format = "swappy-%Y%m%d-%H%M%S.png";
    };
  };
}
