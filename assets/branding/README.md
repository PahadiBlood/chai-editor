# Chai Editor logo

Original vector artwork: a folded document and a chai cup, in cream and amber
on a dark rounded square. `chai-logo.svg` is the editable master;
`chai-logo.png` is the 1024 px transparent PNG companion. Both were drawn
programmatically; no image-generation service or stock assets were used.

`ChaiIcon.appiconset` supplies all macOS icon sizes. `./setup.sh` copies it into
the runner and selects it. The original Flutter `AppIcon` asset remains intact;
run `CHAI_USE_CUSTOM_ICON=0 ./setup.sh` to select that original icon again.

To rerender the PNG master, run `swift tools/render_logo.swift` from the project
root. The script mirrors the SVG geometry using AppKit.
