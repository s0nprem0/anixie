{ pkgs, ... }:

{
  fonts.packages = with pkgs; [
    # The shell's own face, and the glyph fonts the bar leans on.
    nerd-fonts.jetbrains-mono
    nerd-fonts.gohufont
    nerd-fonts.symbols-only

    # Text and emoji that documents and web pages expect to find. Without the
    # Noto families a PDF or a page in a script the default font lacks turns into
    # boxes, which is a bad first impression of a working machine.
    noto-fonts
    noto-fonts-color-emoji

    # Microsoft's fonts: the core set (Arial, Times New Roman, Courier New) that
    # old documents and the web still assume, plus the Vista/Office families
    # (Calibri, Cambria, Consolas) that modern .docx and .pptx files specify.
    corefonts
    vista-fonts

    # Text laid over a photo: Inter for small captions and watermarks, Fraunces
    # for a display line. The UI's mono is wrong for both — a caption needs a
    # neutral grotesque, and a title needs a face with some edge.
    inter
    fraunces

    # Other patched families, for the applications that let you choose: FiraCode
    # for the floating title bars, Hack and Victor Mono for the editors and
    # terminals that read better at small sizes.
    #
    # Iosevka and the Nerd Font build of Noto used to be here too. They are not
    # referenced anywhere in the tree, and they are the two largest font trees
    # in nixpkgs — 1.1 GiB and 1.0 GiB unpacked — for glyph coverage `noto-fonts`
    # above already provides. Dropping them takes ~2.2 GiB out of the closure and
    # the fontconfig cache; add one back if a specific app wants it.
    nerd-fonts.fira-code
    nerd-fonts.hack
    nerd-fonts.victor-mono
  ];
}
