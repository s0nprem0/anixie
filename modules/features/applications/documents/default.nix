{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.applications.documents;
in
{
  options.my.applications.documents.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install zathura (PDF reader, the default PDF handler) and xournalpp (PDF annotator).";
  };

  config = lib.mkIf cfg.enable {
    # zathura reads a PDF; xournalpp is the one that fills in the form or signs it,
    # which is the thing a PDF in a laptop's downloads folder usually wants.
    home.packages = [
      pkgs.zathura
      pkgs.xournalpp
    ];

    # VectorCraft claims application/pdf in its desktop entry and Xournal++ does
    # too, so without a stated default the winner is whichever entry is read
    # first. Reading is the common case; xournalpp stays in Open With for the
    # annotate case.
    xdg.mimeApps = {
      enable = true;
      defaultApplications."application/pdf" = "org.pwmt.zathura.desktop";
    };
  };
}
