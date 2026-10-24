{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.sharePicker;

  render = config.anixie.theme.template.render;

  stateDir = config.anixie.theme.stateDir;

  # Rendered once for the first login; theme-apps rewrites the same file in the
  # state directory on every switch, so the picker follows a runtime theme.
  defaultCss = pkgs.writeText "anixie-share-picker.css" (render ./style.css);

  picker = inputs.hyprland-preview-share-picker.packages.${pkgs.stdenv.hostPlatform.system}.default;

  configDir = "${config.xdg.configHome}/hyprland-preview-share-picker";

  # Absolute paths, because the portal does not start this from a login shell:
  # its PATH is the user manager's, not the profile's.
  pickerConfig =
    builtins.replaceStrings
      [ "@STYLE@" "@SLURP@" ]
      [ "${configDir}/style.css" "${pkgs.slurp}/bin/slurp" ]
      (builtins.readFile ./config.yaml);
in
{
  options.anixie.wm.sharePicker.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to use the preview-share picker for portal screen sharing.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ picker ];

    xdg.configFile = {
      "hyprland-preview-share-picker/config.yaml".text = pickerConfig;
      "hyprland-preview-share-picker/style.css".source =
        config.lib.file.mkOutOfStoreSymlink "${stateDir}/share-picker.css";

      # xdg-desktop-portal-hyprland reads this next to the compositor config.
      # The binary is named by full store path so the portal service does not
      # have to resolve it from a user PATH it may not have.
      "hypr/xdph.conf".text = ''
        screencopy {
          custom_picker_binary = ${picker}/bin/hyprland-preview-share-picker
        }
      '';
    };

    home.activation.anixieSharePicker = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      state=${lib.escapeShellArg stateDir}
      mkdir -p "$state"
      [ -f "$state/share-picker.css" ] || install -m 644 ${defaultCss} "$state/share-picker.css"
    '';
  };
}
