# Mac O’ Blox website

A static promotional site for `macoblox.aubree.wtf`, published through GitHub
Pages from the MacOBlox repository's separate `website` branch. The application
release and `main` branch are independent.

## Files and hosting

`dist/` is the complete public site. There is no package installation or build
step. Serve that directory with any static host. The GitHub Actions workflow
at `.github/workflows/website.yml` publishes only `website/dist`, triggered by
website changes pushed to the `website` branch.

For local viewing, run `python3 -m http.server 8080 --directory dist`.
To publish edits, commit and push them to the `website` branch. GitHub Pages
must use **GitHub Actions** as its source, with the `github-pages` environment
allowing the `website` branch. There is no deployment workflow on `main`.

## Custom domain

Set the repository's Pages custom domain to `macoblox.aubree.wtf`. In the
`aubree.wtf` DNS zone, point the `macoblox` CNAME at `aubree-lat.github.io`.
Enable Enforce HTTPS once GitHub has issued the certificate. Sites-specific
verification records are not needed for GitHub Pages.

## Brand and dependencies

- The palette, square window chrome, fonts and exact patched Vanta topology
  backdrop follow [aubree.wtf](https://aubree.wtf).
- `assets/vendor/vanta.topology.min.js` was fetched from aubree.wtf and preserves
  its particle speed patch. Vanta is MIT licensed; p5.js 1.1.9 is LGPL licensed.
- Local Archivo and JetBrains Mono fonts retain their OFL notices.
- Wordmark and screenshots come from the MacOBlox project's existing public
  branding and Flatpak screenshot assets. Images retain their original colors.
- License texts and upstream source references are in `dist/assets/licenses/`.

## Updating the release

The Flatpak download and checksum links currently point to `v0.19`. Update
those links when preparing a new project release. The latest-release link
always follows the current release. Install commands always point to
the application repository's `main` branch. No telemetry or external font
requests are used. The background respects reduced motion and pauses while
the page is hidden.
