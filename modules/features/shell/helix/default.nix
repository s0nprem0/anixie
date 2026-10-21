{ config, pkgs, flakeDir, host, ... }:

let
  # nixd evaluates this flake to complete NixOS and Home Manager options, so it
  # needs the checkout on disk rather than the store copy a build sees.
  flake = ''(builtins.getFlake "${config.home.homeDirectory}/${flakeDir}")'';
  hostExpr = "${flake}.nixosConfigurations.${host}";
in
{
  programs.helix = {
    enable = true;

    # On Helix's PATH only, not the profile's: they are the editor's, and a
    # shell has no use for a language server.
    extraPackages = with pkgs; [
      bash-language-server
      lua-language-server
      marksman
      nixd
      nixfmt
      shfmt
      # qmlls ships in qtdeclarative, not a package of its own.
      kdePackages.qtdeclarative
    ];

    settings.editor = {
      line-number = "relative";
      cursorline = true;
      color-modes = true;
      bufferline = "multiple";

      cursor-shape = {
        normal = "block";
        insert = "bar";
        select = "underline";
      };

      # Errors at the end of their line everywhere, and in full under the
      # cursor, rather than only as a gutter mark to go and hover.
      end-of-line-diagnostics = "hint";
      inline-diagnostics.cursor-line = "warning";

      lsp.display-inlay-hints = true;

      indent-guides = {
        render = true;
        character = "▏";
        skip-levels = 1;
      };

      # Dotfiles are most of this repo. .gitignore is still respected, so the
      # picker does not fill with result/ and .direnv/.
      file-picker.hidden = false;

      auto-save.focus-lost = true;

      statusline = {
        left = [
          "mode"
          "spinner"
          "version-control"
          "file-name"
          "read-only-indicator"
          "file-modification-indicator"
        ];
        right = [
          "diagnostics"
          "selections"
          "register"
          "position"
          "file-type"
        ];
        mode = {
          normal = "NORMAL";
          insert = "INSERT";
          select = "SELECT";
        };
      };
    };

    languages = {
      language-server.nixd.config.nixd = {
        nixpkgs.expr = "import ${flake}.inputs.nixpkgs { }";
        formatting.command = [ "nixfmt" ];
        options = {
          nixos.expr = "${hostExpr}.options";
          home-manager.expr = "${hostExpr}.options.home-manager.users.type.getSubOptions [ ]";
        };
      };

      # Quickshell's types live in its own QML module, which qmlls cannot find
      # on its own: -E has it read the import path from the environment.
      language-server.qmlls = {
        args = [ "-E" ];
        environment.QML_IMPORT_PATH = "${pkgs.quickshell}/lib/qt-6/qml";
      };

      language = [
        {
          name = "nix";
          language-servers = [ "nixd" ];
          formatter.command = "nixfmt";
          auto-format = true;
        }
        {
          # Formatted on :format only. The scripts here follow no one shfmt
          # style, so formatting on save would rewrite most of each file the
          # first time it was touched.
          name = "bash";
          formatter = {
            command = "shfmt";
            args = [
              "-i"
              "2"
              "-ci"
            ];
          };
        }
      ];
    };
  };

  home.sessionVariables = {
    # Helix installs its binary as hx.
    EDITOR = "hx";
    VISUAL = "hx";
  };
}
