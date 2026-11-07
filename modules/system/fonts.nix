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
    # Iosevka Nerd Font is the monospace face used in LibreWolf (and any
    # app that asks for Iosevka): yes it costs ~1.1 GiB, but it is the face
    # the browser is actually set to, so the cost is deliberate.
    # The Nerd Font build of Noto used to be here too; it is not referenced
    # anywhere in the tree and is the other ~1.0 GiB tree, with glyph
    # coverage `noto-fonts` above already provides.
    nerd-fonts.iosevka
    nerd-fonts.fira-code
    nerd-fonts.hack
    nerd-fonts.victor-mono
  ];
}
