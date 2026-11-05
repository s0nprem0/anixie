# The Craft apps storytold publishes as prebuilt Linux tarballs. Each release
# has the same asset name, so the package builder derives the URL from the name
# and version. To move an app to a new release, change its version and hash;
# `nix store prefetch-file --json <url>` prints the hash.
{
  cadcraft = {
    version = "0.17.1";
    hash = "sha256-3aFlovLubh70nHzAJXteA4LetUHY6uAhExdogvny7AA=";
    title = "CADCraft";
    description = "AutoCAD-style CAD and drafting";
  };

  deckcraft = {
    version = "0.15.1";
    hash = "sha256-4tRRKdSw9dKCIyRVtzs10twWpPWHv2mh24CTmwreeM0=";
    title = "DeckCraft";
    description = "PowerPoint-style presentations and slide shows";
  };

  designcraft = {
    version = "0.17.2";
    hash = "sha256-uS6QZ9sRuN4bs0gjLAlV0yRpNm+jlS1d2WwYyhgKKM4=";
    title = "DesignCraft";
    description = "InDesign-style page layout and publishing";
  };

  effectcraft = {
    version = "0.21.1";
    hash = "sha256-7DmvpR+wosC1iowRAjJeI1UBb+dUVj0kB1+imz4cUxU=";
    title = "EffectCraft";
    description = "After Effects-style motion graphics and VFX";
  };

  figcraft = {
    version = "0.15.1";
    hash = "sha256-1Xde+tyLtnOgt0HM2iicHr7Kb7P4J4laQM1X/wnEdNE=";
    title = "FigCraft";
    description = "Figma-style interface design and prototyping";
  };

  filmcraft = {
    version = "0.17.1";
    hash = "sha256-OXrp/s5VmzeGO0sHavRqY7bkOHw194Fwnk760U/nHr4=";
    title = "FilmCraft";
    description = "Premiere-style video editor";
  };

  gridcraft = {
    version = "0.16.1";
    hash = "sha256-Qp4DNM3TDtdev/WUU6ZEEUw8t+M0eZGoGzIEHXX0H+Q=";
    title = "GridCraft";
    description = "Excel-style spreadsheet";
  };

  lightcraft = {
    version = "0.18.1";
    hash = "sha256-B4+OT+9sqIr6JXpwIoYwsU4hOAzqWAMfu1xaGUK0BvA=";
    title = "LightCraft";
    description = "Lightroom-style photo library and raw processor";
  };

  pdfcraft = {
    version = "0.18.2";
    hash = "sha256-MjutezczkgdkYeLK1dtjsi9HoDK6AFpsSjXzSD0F2uQ=";
    title = "PdfCraft";
    description = "Acrobat-style PDF reader, organizer and editor";
  };

  photocraft = {
    version = "0.20.2";
    hash = "sha256-CeAT1o2DE+sLHNbyRhL1tf0NmT//46fBLOzf5c0TGkY=";
    title = "PhotoCraft";
    description = "Photoshop-style image editor";
  };

  soundcraft = {
    version = "0.17.1";
    hash = "sha256-56wUC7n9aa3k3QJkOvjl1MFKXILNZwsgMOUmiP67PLQ=";
    title = "SoundCraft";
    description = "Pro Tools-style audio workstation";
  };

  vectorcraft = {
    version = "0.21.1";
    hash = "sha256-ODu6BvvefLh8fhN5N61RappYVJHFqSfYYx7lS78dTpM=";
    title = "VectorCraft";
    description = "Illustrator-style vector illustration";
  };

  wordcraft = {
    version = "0.15.2";
    hash = "sha256-Nm5U4jW0Yxd5wMeMB3eogN5REWPekTCreM5ZWD96C5o=";
    title = "WordCraft";
    description = "Word-style word processor";
  };
}
