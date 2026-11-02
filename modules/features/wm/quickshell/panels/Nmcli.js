.pragma library

// nmcli's terse output (`-t`, `-g`) escapes `:` and `\` with a backslash. A
// profile or SSID name has to be unescaped before it is shown or passed back to
// a con verb.
function decode(value) {
  return String(value).replace(/\\(.)/g, "$1")
}
