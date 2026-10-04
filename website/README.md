# Mac O’ Blox website

A static promotional site for `macoblox.aubree.wtf`. Website and application
source share the repository's `main` branch. Installer and launcher updates
exclude the website and hosting configuration; Flatpak builds also skip them.

## Files and hosting

`dist/` is the complete public site. There is no package installation or build
step. Serve that directory with any static host. Repository-root `vercel.json`
selects the Other framework, skips install and build commands, and serves only
`website/dist`. `.vercelignore` limits Vercel CLI uploads to website source and
hosting configuration.

For local viewing, run `python3 -m http.server 8080 --directory dist`.
For Vercel, import `aubree-lat/MacOBlox` with the repository root (`./`) as the
Root Directory and `main` as the Production Branch. The checked-in config
supplies Framework Preset **Other**, empty Build/Install Commands, and Output
Directory `website/dist`. Push website edits to `main` to publish through the
connected Vercel project. See [Vercel's configuration documentation](https://vercel.com/docs/project-configuration/vercel-json).

## Custom domain

Add `macoblox.aubree.wtf` under the Vercel project's Domains settings. Replace
the previous GitHub Pages CNAME with the DNS record shown by Vercel for that
domain. GitHub Pages and Sites verification records are not used by this host.

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
