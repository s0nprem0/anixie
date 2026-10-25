def color($m; $name): $m.colors[$name].default.color;

. as $m |
($m.mode // $fallback // "dark") as $mode |
(if $mode == "light" then { success: "#2f7d32", yellow: "#9a6700" }
 else { success: "#a6e3a1", yellow: "#f0c674" } end) as $semantic |
(if $mode == "light"
 then { bgDark: color($m; "surface_container_highest"), bgLight: color($m; "surface_container_lowest") }
 else { bgDark: color($m; "surface_container_lowest"), bgLight: color($m; "surface_container_highest") } end) as $levels |
{
  background: color($m; "background"),
  surface: color($m; "surface_container"),
  surfaceContainer: color($m; "surface_container_high"),
  surfaceVariant: color($m; "surface_variant"),
  foreground: color($m; "on_background"),
  fgLight: color($m; "on_surface_variant"),
  bgDark: $levels.bgDark,
  bgLight: $levels.bgLight,
  muted: color($m; "on_surface_variant"),
  outline: color($m; "outline"),
  primary: color($m; "primary"),
  accent: color($m; "tertiary"),
  accentAlt: color($m; "secondary"),
  secondary: color($m; "secondary"),
  tertiary: color($m; "tertiary"),
  success: $semantic.success,
  yellow: $semantic.yellow,
  danger: color($m; "error"),
  error: color($m; "error"),
  ansi0: color($m; "background"),
  ansi1: color($m; "error"),
  ansi2: $semantic.success,
  ansi3: $semantic.yellow,
  ansi4: color($m; "primary"),
  ansi5: color($m; "secondary"),
  ansi6: color($m; "tertiary"),
  ansi7: color($m; "on_background"),
  ansi8: color($m; "on_surface_variant"),
  ansi9: color($m; "error"),
  ansi10: $semantic.success,
  ansi11: $semantic.yellow,
  ansi12: color($m; "primary"),
  ansi13: color($m; "secondary"),
  ansi14: color($m; "tertiary"),
  ansi15: color($m; "on_background"),
  _mode: (if $mode == "light" or $mode == "dark" then $mode else "dark" end)
}
