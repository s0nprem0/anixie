# The Craft apps storytold publishes as prebuilt Linux tarballs. Each release
# has the same asset name, so the package builder derives the URL from the name
# and version. To move an app to a new release, change its version and hash;
# `nix store prefetch-file --json <url>` prints the hash.
{
  cadcraft = {
    version = "0.18.0";
    hash = "sha256-DVtSKvz6IMfliIfCCS+1rVMi65DB2pgGHmG346zRvtU=";
    title = "CADCraft";
    description = "AutoCAD-style CAD and drafting";
  };

  deckcraft = {
    version = "0.16.0";
    hash = "sha256-7tVysvYjldD1z+JGpygYllHpXk7N9MPgrYe3ejgx4IY=";
    title = "DeckCraft";
    description = "PowerPoint-style presentations and slide shows";
  };

  designcraft = {
    version = "0.18.0";
    hash = "sha256-U5h8tmvn3pOFTtVwAEJ/vhwHKgQnvIy69QH/NnLVQyw=";
    title = "DesignCraft";
    description = "InDesign-style page layout and publishing";
  };

  effectcraft = {
    version = "0.22.0";
    hash = "sha256-X+mwrldGrCm2H33qEL1ntx6ZbB4BiIJMT4GpZiPDvuk=";
    title = "EffectCraft";
    description = "After Effects-style motion graphics and VFX";
  };

  figcraft = {
    version = "0.16.0";
    hash = "sha256-1ef5n0nTpwPX9SQYVNx1b7PVX8lNDJXSlw24SjM5H1o=";
    title = "FigCraft";
    description = "Figma-style interface design and prototyping";
  };

  filmcraft = {
    version = "0.18.0";
    hash = "sha256-AXnwWyDbhVv9Pe+RNs5g3uWfItLcv88j5KYlbgwVOwU=";
    title = "FilmCraft";
    description = "Premiere-style video editor";
  };

  gridcraft = {
    version = "0.17.0";
    hash = "sha256-FOk3RVW8bS2cW8QbsxFQvGoctrToPVq0Fj/V12EbBhg=";
    title = "GridCraft";
    description = "Excel-style spreadsheet";
  };

  lightcraft = {
    version = "0.19.0";
    hash = "sha256-lIXWS9vpjG2vutDqeqwPpJQw0KAIuaZrpD3+d7dVUok=";
    title = "LightCraft";
    description = "Lightroom-style photo library and raw processor";
  };

  pdfcraft = {
    version = "0.19.0";
    hash = "sha256-NleqQP4UbUr0D6sFB8l/buLGzlupk4VnGUQ5vjM1uos=";
    title = "PdfCraft";
    description = "Acrobat-style PDF reader, organizer and editor";
  };

  photocraft = {
    version = "0.21.0";
    hash = "sha256-MRXlbMZG2601QeObYyO4okMY/uYZTXhN320GX3tdLTc=";
    title = "PhotoCraft";
    description = "Photoshop-style image editor";
  };

  soundcraft = {
    version = "0.18.0";
    hash = "sha256-M40f5yuWkqXZn/Q1UD31jIU/W5bC6VsoIdiD8x+LWmY=";
    title = "SoundCraft";
    description = "Pro Tools-style audio workstation";
  };

  vectorcraft = {
    version = "0.22.0";
    hash = "sha256-boEqksrsTboj/XRzT6IKMniG7yBCe1Xy+If+kzSgkz8=";
    title = "VectorCraft";
    description = "Illustrator-style vector illustration";
  };

  wordcraft = {
    version = "0.16.0";
    hash = "sha256-MluX8Vu/UyYooxdqnBcUinF18+Txm5MT3jI6tRNgl1I=";
    title = "WordCraft";
    description = "Word-style word processor";
  };
}
