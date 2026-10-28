# The Craft apps storytold publishes as prebuilt Linux tarballs. Each release
# has the same asset name, so the package builder derives the URL from the name
# and version. To move an app to a new release, change its version and hash;
# `nix store prefetch-file --json <url>` prints the hash.
{
  photocraft = {
    version = "0.15.1";
    hash = "sha256-tiK+QDVVEwVvgVKv6JXQoFwbw8NEoCf3cqmhL6PRwiM=";
    title = "PhotoCraft";
    description = "Photoshop-style image editor";
  };

  vectorcraft = {
    version = "0.16.0";
    hash = "sha256-ZR+sFyVSca0dvIuh6Ch9ufKOUpupoU3QOD7Kk6LMWqY=";
    title = "VectorCraft";
    description = "Illustrator-style vector illustration";
  };

  effectcraft = {
    version = "0.16.0";
    hash = "sha256-kbQNqeGL5JFXRnqW23svv3wgtRgtjEFcWb7VFZG8HeA=";
    title = "EffectCraft";
    description = "After Effects-style motion graphics and VFX";
  };

  filmcraft = {
    version = "0.12.0";
    hash = "sha256-3f8KLsDYnl6eZWRO1yS1t5lZYAsWAv1OpmU7WlS/iP0=";
    title = "FilmCraft";
    description = "Premiere-style video editor";
  };

  soundcraft = {
    version = "0.12.1";
    hash = "sha256-sKVr1rXSfeaxLjVFgMNivm9ZEl6lj1cwRMhPan2od4A=";
    title = "SoundCraft";
    description = "Pro Tools-style audio workstation";
  };

  wordcraft = {
    version = "0.10.0";
    hash = "sha256-ypnqNQugrqQQP8gCDK2Y8FHFjZ6fz2cMEZ2BAQjMRf8=";
    title = "WordCraft";
    description = "Word-style word processor";
  };

  deckcraft = {
    version = "0.10.0";
    hash = "sha256-VGYW6yMAzo77ILRKU+YKv+a5bXGsYGtFKjb9Icax/yg=";
    title = "DeckCraft";
    description = "PowerPoint-style presentations and slide shows";
  };

  gridcraft = {
    version = "0.11.1";
    hash = "sha256-8sg+bCZEmmxFmD6QO/MsHUwwKyBC8mPq2ZUnESnHDoc=";
    title = "GridCraft";
    description = "Excel-style spreadsheet";
  };

  lightcraft = {
    version = "0.14.0";
    hash = "sha256-uCM7k3PW6ZsRgMHDn9yxPUnEQfgAkncIMfqxlcTE/aI=";
    title = "LightCraft";
    description = "Lightroom-style photo library and raw developer";
  };
}
