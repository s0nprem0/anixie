import QtQuick
import ".."

// A Dropdown that always shows a filter field in its popup. Convenience wrapper
// around Dropdown with `searchable: true`, so callers do not have to remember
// to enable it. Use for lists long enough to benefit from narrowing (DNS
// providers, bands, themes, …).
Dropdown {
  searchable: true
}
