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

    # Other patched families, for the applications that let you choose: a
    # proportional one for prose, a condensed one for terminals, and the ones
    # that read better at small sizes.
    nerd-fonts.fira-code
    nerd-fonts.noto
    nerd-fonts.hack
    nerd-fonts.iosevka
    nerd-fonts.victor-mono
  ];
}
