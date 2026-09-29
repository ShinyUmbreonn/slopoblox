<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="branding/wordmark-dark.png">
    <img src="branding/wordmark-light.png" alt="Mac O’ Blox" width="520">
  </picture>
</p>

<p align="center">
  The real macOS Roblox client, running on Linux through <a href="https://www.darlinghq.org">Darling</a>.
  improved by aubree.wtf with patches and more, originally created by narizy, credits to them.
</p>

<p align="center">
  <a href="https://discord.gg/jCjHYYNq48"><img src="https://img.shields.io/badge/Discord-join-5865F2?logo=discord&logoColor=white" alt="Discord"></a>
</p>

<br>

Full graphics with antialiasing, sound, camera and mouse lock, a session that
survives restarts, and a small launcher with fast flags. Roblox Studio too, in
its Windows version through Wine. English and Russian.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/aubree-lat/MacOBlox/main/install.sh | bash
```

It installs Darling and everything else, then puts **Mac O’ Blox** in the app
menu. Open it, press **Install Roblox**, then **Play**. Run the same command
again for a small menu to update or uninstall. Without a terminal, or for
scripts, the choices are options too:

```bash
curl -fsSL https://raw.githubusercontent.com/aubree-lat/MacOBlox/main/install.sh | bash -s -- --uninstall
```

Uninstalling keeps Darling and its prefix, `~/.darling`, which holds your Roblox
sign-in; `--purge` (or **Uninstall everything** in the menu) deletes that too.

Works on Arch and its relatives (CachyOS, EndeavourOS, Manjaro), Ubuntu 24.04+,
Debian 13, Linux Mint 22 and Fedora with Darling built from source.

<details>
<summary>Install by hand</summary>

**1. Darling and the tools**

Arch, CachyOS, EndeavourOS, Manjaro:

```bash
paru -S darling-bin
sudo pacman -S clang lld unzip pipewire-audio python-gobject gtk4 libadwaita webkitgtk-6.0
```

Debian, Ubuntu, Mint: download `debs_20260608.zip` from the
[Darling release v0.1.20260608](https://github.com/darlinghq/darling/releases/tag/v0.1.20260608)
(the one Mac O’ Blox is tested with), then:

```bash
unzip debs_*.zip -d darling-debs
sudo apt install ./darling-debs/*/*.deb
sudo apt install clang lld unzip pipewire-bin python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 gir1.2-webkit-6.0
```

Fedora and others: build Darling with the
[official guide](https://docs.darlinghq.org/build-instructions.html), then:

```bash
sudo dnf install clang lld unzip pipewire-utils python3-gobject gtk4 libadwaita webkitgtk6.0
```

**2. Mac O’ Blox**

```bash
git clone https://github.com/aubree-lat/MacOBlox ~/.local/share/MacOBlox
~/.local/share/MacOBlox/launcher/install.sh
```
</details>

## Questions

<details>
<summary>Is my account safe?</summary>

You sign in inside Roblox itself, the launcher never sees your password. The
session is stored only on your computer, in
`~/.darling/Users/$USER/Library/MacOBlox`. Do not share that folder, it works
like a password. **Sign out** in the settings deletes it.

Mac O’ Blox is not made by Roblox, using it is at your own risk.
</details>

<details>
<summary>Something does not work</summary>

When Roblox does not start, the launcher shows the error with a **Copy**
button. Send it to the [Discord](https://discord.gg/jCjHYYNq48). The last
error is also saved in `~/.cache/macoblox/last-error.txt`.
</details>

<details>
<summary>How do I sign in?</summary>

Signing up and signing in with a password show a captcha in a web page, which
Darling cannot display; Mac O’ Blox opens it in a window of its own instead
(it needs WebKitGTK 6.0, which the installer brings along). Without that
window, create the account on [roblox.com](https://www.roblox.com) first and
sign in in Mac O’ Blox with **Quick Login**: Roblox shows a code, enter it on a
phone or in a browser where you are already signed in.
</details>

<details>
<summary>Images or servers do not load</summary>

Some providers break Roblox's addresses. In **Settings → DNS for Roblox** pick
Quad9 or Cloudflare. Only Roblox uses it, the rest of the system keeps its DNS.
</details>

<details>
<summary>Roblox Studio</summary>

Press **Roblox Studio** in the launcher. The first time it downloads Wine, DXVK
and Studio (about 800 MB) into its own folder, nothing is installed system-wide.
To sign in, Studio opens the Roblox login in your browser; when the browser asks
how to open the `roblox-studio-auth` link, choose **Roblox Studio (Mac O’ Blox)**.
</details>

<details>
<summary>Flatpak (testing)</summary>

The Flatpak brings Darling along and runs it without root (see
[flatpak/darling-noroot.c](flatpak/darling-noroot.c)), so nothing has to be
installed on the system. Download `MacOBlox-*.flatpak` from the
[latest release](https://github.com/aubree-lat/MacOBlox/releases/latest), then:

```bash
flatpak install --user MacOBlox-0.15-x86_64.flatpak
```

It keeps its own Darling prefix, so sign in to Roblox again there. Roblox Studio
is not in the Flatpak yet. To build it yourself:

```bash
flatpak install --user flathub org.flatpak.Builder org.gnome.Sdk//50 org.freedesktop.Sdk.Extension.llvm22//25.08
cd MacOBlox/flatpak
flatpak run --env=FLATPAK_USER_DIR=$HOME/.local/share/flatpak --command=flatpak-builder org.flatpak.Builder --user --install --force-clean build-dir wtf.aubree.MacOBlox.yml
```
</details>

<details>
<summary>How does it work?</summary>

Darling runs macOS programs on Linux. Roblox needs a few things Darling does not
have yet, so Mac O’ Blox adds a small library to the game: it connects the mouse,
sound, OpenGL and network to Linux and fixes bugs along the way. Details are in
[docs/NOTES.md](docs/NOTES.md).
</details>

## Credits

Made by [Narezany](https://github.com/narezy). This version is maintained by
[aubree.wtf](https://aubree.wtf), with stability and performance fixes.

[Darling](https://www.darlinghq.org) · Tux by Larry Ewing and The GIMP ·
[Comfortaa](https://github.com/alexeiva/comfortaa) font (SIL OFL) ·
icons from [Simple Icons](https://simpleicons.org)

Mac O’ Blox is MIT licensed. Not affiliated with Roblox Corporation.
