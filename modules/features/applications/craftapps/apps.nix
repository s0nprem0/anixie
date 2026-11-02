# The Craft apps storytold publishes as prebuilt Linux tarballs. Each release
# has the same asset name, so the package builder derives the URL from the name
# and version. To move an app to a new release, change its version and hash;
# `nix store prefetch-file --json <url>` prints the hash.
{
  cadcraft = {
    version = "0.16.0";
    hash = "sha256-FJggs9Dh5ymiJW40RSO5gFhx057jnJ4IX1B3B/c8y9Q=";
    title = "CADCraft";
    description = "AutoCAD-style CAD and drafting";
  };

  deckcraft = {
    version = "0.14.1";
    hash = "sha256-6Gx/oOy1XxpVPuQluT3P3IBrezeY8nK0Hx0f90rFwSo=";
    title = "DeckCraft";
    description = "PowerPoint-style presentations and slide shows";
  };

  designcraft = {
    version = "0.16.0";
    hash = "sha256-pIb8Q83I8kXtr3N8uxyaMoYO4YqNyhuv4IERAU4vFXY=";
    title = "DesignCraft";
    description = "InDesign-style page layout and publishing";
  };

  effectcraft = {
    version = "0.20.0";
    hash = "sha256-JXMQCgos4HppJXvaf6an1SUtO00y3+86H20slby42iM=";
    title = "EffectCraft";
    description = "After Effects-style motion graphics and VFX";
  };

  figcraft = {
    version = "0.14.0";
    hash = "sha256-DqSJzimSOK+WEGlAzdtCCRw+uhCcBf34Q7Tn+OuXCCk=";
    title = "FigCraft";
    description = "Figma-style interface design and prototyping";
  };

  filmcraft = {
    version = "0.16.0";
    hash = "sha256-WIOQ7uXX4WNPBXlMT4d93ylJTZz3RAURHWfBbL4hWuk=";
    title = "FilmCraft";
    description = "Premiere-style video editor";
  };

  gridcraft = {
    version = "0.15.0";
    hash = "sha256-aBD4znOUtafN+vOYOCV7Y4Tc65+DJQJNR124le5Z2qo=";
    title = "GridCraft";
    description = "Excel-style spreadsheet";
  };

  lightcraft = {
    version = "0.17.0";
    hash = "sha256-0Yf1oVktSGYiDE0SfW5aPaT/p8lmzIffj0nnNcB88sE=";
    title = "LightCraft";
    description = "Lightroom-style photo library and raw processor";
  };

  pdfcraft = {
    version = "0.17.0";
    hash = "sha256-+YFKegr3e5Ba26HDB5yu3uU3WGeXBDz1r5UDkU9qvsU=";
    title = "PdfCraft";
    description = "Acrobat-style PDF reader, organizer and editor";
  };

  photocraft = {
    version = "0.19.0";
    hash = "sha256-EjOFsXMKzhjxK8D0lGBuakzT9KuJH5MDbNTnG4rqcPc=";
    title = "PhotoCraft";
    description = "Photoshop-style image editor";
  };

  soundcraft = {
    version = "0.16.0";
    hash = "sha256-Jcawy4kkGY8i46bydx19zJ4EGjJEpL5EXL3p0A59wZ4=";
    title = "SoundCraft";
    description = "Pro Tools-style audio workstation";
  };

  vectorcraft = {
    version = "0.20.0";
    hash = "sha256-042D2eWf3PehAEFOIrMJQJT+T+LdQ6EF8EKXgBJhDoY=";
    title = "VectorCraft";
    description = "Illustrator-style vector illustration";
  };

  wordcraft = {
    version = "0.14.0";
    hash = "sha256-MBDaPTUtlSVuyaF6A5ZigKHUG6CdDr5WmvIwkti2SYc=";
    title = "WordCraft";
    description = "Word-style word processor";
  };
}
