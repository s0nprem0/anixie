# The Craft apps storytold publishes as prebuilt Linux tarballs. Each release
# has the same asset name, so the package builder derives the URL from the name
# and version. To move an app to a new release, change its version and hash;
# `nix store prefetch-file --json <url>` prints the hash.
{
  cadcraft = {
    version = "0.15.1";
    hash = "sha256-0ETw+KdVxrab3GtFNh2rzDQsFOOxkZw59UBp/80cT4A=";
    title = "CADCraft";
    description = "AutoCAD-style CAD and drafting";
  };

  deckcraft = {
    version = "0.13.1";
    hash = "sha256-cR7AlbWQ+8uqq8jFklqDUN6pjukxq3tE1Ir2iy5h9RQ=";
    title = "DeckCraft";
    description = "PowerPoint-style presentations and slide shows";
  };

  designcraft = {
    version = "0.15.2";
    hash = "sha256-57eC90ZJd+/pNa1o48kIsJOfO2ZgcMiN8gRhmNxuiUQ=";
    title = "DesignCraft";
    description = "InDesign-style page layout and publishing";
  };

  effectcraft = {
    version = "0.19.0";
    hash = "sha256-fsk5Ha53X3zn5ykSaPexIzIowbreg87YhAMDU1yVGXA=";
    title = "EffectCraft";
    description = "After Effects-style motion graphics and VFX";
  };

  figcraft = {
    version = "0.13.1";
    hash = "sha256-hlzynHWnN82FnZP6SOnUqo3GAj8liqEn6IuX2If5DSc=";
    title = "FigCraft";
    description = "Figma-style interface design and prototyping";
  };

  filmcraft = {
    version = "0.15.0";
    hash = "sha256-IrEGtMpilNmz6aSvQLQKZToYl0NzZIBQRqAd26pLIsE=";
    title = "FilmCraft";
    description = "Premiere-style video editor";
  };

  gridcraft = {
    version = "0.14.2";
    hash = "sha256-nIFTt2MK373vgCGqm5guHvGHts8nzSIzKAz68LpqGEI=";
    title = "GridCraft";
    description = "Excel-style spreadsheet";
  };

  lightcraft = {
    version = "0.16.0";
    hash = "sha256-0i7fWsQBACkdjD2N3ovxyRyuIaC1bUypzAAm2zE5qSY=";
    title = "LightCraft";
    description = "Lightroom-style photo library and raw processor";
  };

  pdfcraft = {
    version = "0.16.1";
    hash = "sha256-uzbgcdEKFK9RISmaDu2NfF245cdYC2y+vsCFxB0b/go=";
    title = "PdfCraft";
    description = "Acrobat-style PDF reader, organizer and editor";
  };

  photocraft = {
    version = "0.18.0";
    hash = "sha256-S4rI4RRqyal+e/3vFrJn1Tlqd4Cf1OIym4Pa14CGV08=";
    title = "PhotoCraft";
    description = "Photoshop-style image editor";
  };

  soundcraft = {
    version = "0.15.0";
    hash = "sha256-Fu8j72LsIPX8xT4Eq6r/UnCV5QX1YItHqxtyscjp7SA=";
    title = "SoundCraft";
    description = "Pro Tools-style audio workstation";
  };

  vectorcraft = {
    version = "0.19.0";
    hash = "sha256-rlN4iPSWkZqosxk+om8F/SWEvgDv+G2AoH4mRPEGHpI=";
    title = "VectorCraft";
    description = "Illustrator-style vector illustration";
  };

  wordcraft = {
    version = "0.13.2";
    hash = "sha256-bPT8wDCi1PuvM0+dbGDXPCof3uKmlRwGfl+hFf4Qc48=";
    title = "WordCraft";
    description = "Word-style word processor";
  };
}
