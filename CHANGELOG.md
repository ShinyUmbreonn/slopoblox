# Release notes

## 0.18 — 2026-10-04

### Setup

- The terminal installer now welcomes you, explains its destination and system
  packages, shows four installation steps, and gives clear next steps.
- First launch has a welcome, installation overview, download progress, retry
  screen and sign-in guidance. Reopen it from **Setup guide** in the menu.
- Existing installations keep their settings and Roblox session. Source updates
  back up local changes before replacing tracked files and preserve other files.

### Bug fixes

- Fix raw mouse and right-click camera freezes caused by synchronous modifier
  queries. Bound event processing and preserve mouse deltas and button events.
- Restore requested mouse capture after Alt-Tab or another focus change.
- Fix crashes while rendering Private Servers and other embedded pages; improve
  browser bridge timeouts and page closure handling.
- Improve Zink context switching, drawable handling, shader compatibility,
  GPU memory reporting and frame pacing.
- Reduce Darling file-close cleanup costs during the initial leave-game
  transition. Repair event wakeups and lock error handling.
- Keep cleanup within the selected Darling prefix and use stable process
  handles to avoid affecting other app environments.

### Verification and remaining work

The repaired input, focus, Private Servers and initial leave transition were
checked with the actual macOS client on an RTX 3060 Ti using Xwayland. Native
regressions and mocked launcher/process regressions passed. The installer and
setup changes received syntax/build checks and a local visual preview; system
package installation was not repeated for this release.

A later approximately 10–11 second pause after leaving a game is still under
investigation. Intermittent graphics stutters need more gameplay measurements.
Vulkan gameplay still uses Mesa Zink; the Metal-to-Vulkan work is a prototype.
Native Wayland is an opt-in experimental feature and is not complete.
