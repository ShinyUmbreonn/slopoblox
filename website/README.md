# Mac O’ Blox website

A static promotional site for `macoblox.aubree.wtf`, published through Sites.
The source is mirrored under `website/` on the MacOBlox repository's separate
`website` branch. The application release and `main` branch are independent.

## Files and hosting

`dist/` is the complete public site. There is no package installation or build
step. Serve that directory with any static host. Sites uses the identity and
static directory in `.openai/hosting.json`.

For local viewing, run `python3 -m http.server 8080 --directory dist`.
To publish edits, use Sites' normal source workflow and the existing project
ID. Do not register a new Site for this source.

## Brand and dependencies

- The palette, square window chrome, fonts and exact patched Vanta topology
  backdrop follow [aubree.wtf](https://aubree.wtf).
- `assets/vendor/vanta.topology.min.js` was fetched from aubree.wtf and preserves
  its particle speed patch. Vanta is MIT licensed; p5.js 1.1.9 is LGPL licensed.
- Local Archivo and JetBrains Mono fonts retain their OFL notices.
- Wordmark and screenshots come from the MacOBlox project's existing public
  branding and Flatpak screenshot assets. Images are displayed in grayscale.
- License texts and upstream source references are in `dist/assets/licenses/`.

## Updating the release

The release badge and Flatpak links currently point to `v0.19`. Update those
links when preparing a new project release. Install commands always point to
the application repository's `main` branch. No telemetry or external font
requests are used. The background can be paused and respects reduced motion.
