# Custom bar modules

Drop a QML file here and reference it from `bar.json` (or `shell.json`) with
`"type": "qml"`:

```json
{ "id": "gpu", "type": "qml" }
```

The file is expected at `modules/gpu.qml` relative to this directory. Set
`"source"` on the entry to point anywhere else, absolute or relative to the
quickshell config directory.

A module should be an `Item` with `implicitWidth` and `implicitHeight`, and
may declare these properties, which the bar fills in after loading:

  property var bar         // the bar handle: colors, fonts, position, run(), ...
  property string moduleName
  property var settings   // the layout entry that loaded it

See `Ui/Bar.qml` for the full list of properties `bar` exposes.
