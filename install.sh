#!/usr/bin/env bash
# Mac O' Blox installer: Darling, the tools the launcher needs, and the
# launcher itself with its app menu entry. Run it again to update, or to
# uninstall.
#
#   curl -fsSL https://raw.githubusercontent.com/aubree-lat/MacOBlox/main/install.sh | bash
#
# In a terminal it shows a small menu; without one it installs. The choices
# also work as options (with curl: ... | bash -s -- --uninstall), see --help.
#
# Everything runs inside main(), called on the last line, so a download cut
# off halfway does nothing. The exit on that same line matters: main points
# stdin at the terminal (curl | bash), and bash would then read and run
# whatever is typed there as the rest of the script.

set -euo pipefail

REPO=https://github.com/aubree-lat/MacOBlox.git
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
DIR=$DATA_HOME/MacOBlox
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
PREFIX=${DPREFIX:-$HOME/.darling}
# Darling's Debian packages, pinned to the release the Flatpak uses
# (flatpak/wtf.aubree.MacOBlox.yml; change both together). The checksum makes
# sure the download is that release, and a new Darling release cannot break
# installs before the shim was tested with it.
DARLING_TAG=v0.1.20260608
DARLING_DEBS_SHA256=27469ef3932da2e91dd7fb34b70e3628a3e54b7af9fb5480051f44af35eca1fd

# Colours unless NO_COLOR is set or the output is no terminal; arrows and
# dots only where the locale is UTF-8.
if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
  BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m' ACCENT=$'\033[1;35m'
  GOOD=$'\033[1;32m' BAD=$'\033[1;31m' SELECTED=$'\033[1;97;45m'
  SHADES=($'\033[38;5;213m' $'\033[38;5;177m' $'\033[38;5;141m' $'\033[38;5;105m')
else
  BOLD='' DIM='' RESET='' ACCENT='' GOOD='' BAD='' SELECTED=''
  SHADES=('' '' '' '')
fi
case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in
  *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*)
    POINTER='❯' BULLET='•' ON='●' OFF='○' KEYS='↑/↓ move · enter choose · q quit' ;;
  *) POINTER='>' BULLET='-' ON='*' OFF='-' KEYS='up/down move, enter choose, q quit' ;;
esac

say() { printf '%s==>%s %s\n' "$ACCENT" "$RESET" "$*"; }
die() { printf '%sError:%s %s\n' "$BAD" "$RESET" "$*" >&2; exit 1; }

# ------------------------------------------------------------------ install

install_arch() {
  # Only packages that are not installed at all: asking pacman for an
  # installed but outdated one (pipewire-audio 1.6.8 with 1.6.9 in the repo)
  # makes it a partial upgrade that breaks on pinned dependencies.
  local wanted=(git base-devel clang lld unzip python python-gobject gtk4 libadwaita webkitgtk-6.0)
  command -v pw-cat >/dev/null || wanted+=(pipewire-audio)
  local missing
  missing=$(pacman -T "${wanted[@]}" || true)
  if [[ -n $missing ]]; then
    say "Installing tools (pacman): $(echo $missing)"
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm $missing ||
      die "pacman could not install them. Update the system with 'sudo pacman -Syu' and run this again."
  fi
  command -v darling >/dev/null && return
  say "Installing Darling from the AUR (darling-bin)"
  if command -v paru >/dev/null; then
    paru -S --needed --noconfirm --skipreview darling-bin
  elif command -v yay >/dev/null; then
    yay -S --needed --noconfirm --answerdiff None --answerclean None darling-bin
  else
    local build
    build=$(mktemp -d)
    git clone --depth 1 https://aur.archlinux.org/darling-bin.git "$build/darling-bin"
    (cd "$build/darling-bin" && makepkg -si --noconfirm)
    rm -rf "$build"
  fi
}

install_debian() {
  say "Installing tools (apt)"
  sudo apt-get update
  sudo apt-get install -y git curl unzip clang lld pipewire-bin python3 python3-gi \
    gir1.2-gtk-4.0 gir1.2-adw-1 gir1.2-webkit-6.0
  command -v darling >/dev/null && return
  # Release v0.1.YYYYMMDD has its Debian packages (built for Ubuntu 24.04)
  # as debs_YYYYMMDD.zip.
  local build
  say "Installing Darling $DARLING_TAG"
  build=$(mktemp -d)
  curl -fL --progress-bar -o "$build/debs.zip" \
    "https://github.com/darlinghq/darling/releases/download/$DARLING_TAG/debs_${DARLING_TAG##*.}.zip"
  if ! printf '%s  %s\n' "$DARLING_DEBS_SHA256" "$build/debs.zip" | sha256sum -c --quiet -; then
    rm -rf "$build"
    die "The Darling download does not match its checksum. Try again later."
  fi
  unzip -q "$build/debs.zip" -d "$build"
  sudo apt-get install -y "$build"/debs_*/*.deb
  rm -rf "$build"
}

install_fedora() {
  say "Installing tools (dnf)"
  sudo dnf install -y git clang lld unzip pipewire-utils python3-gobject gtk4 libadwaita webkitgtk6.0
}

do_install() {
  [[ $(uname -m) == x86_64 ]] || die "Darling runs only on x86_64."
  [[ -r /etc/os-release ]] && . /etc/os-release
  local family=" ${ID:-} ${ID_LIKE:-} "
  case "$family" in
    *" arch "*) install_arch ;;
    *" debian "* | *" ubuntu "*) install_debian ;;
    *" fedora "*) install_fedora ;;
    *)
      # Derivatives that do not say what they are based on (LeagueArchy has
      # no ID_LIKE): go by the package manager.
      if command -v pacman >/dev/null; then install_arch
      elif command -v apt-get >/dev/null; then install_debian
      elif command -v dnf >/dev/null; then install_fedora
      else say "Unknown distribution, install Darling, clang, lld, unzip, PipeWire, PyGObject, GTK 4 and libadwaita yourself"
      fi ;;
  esac
  for tool in clang ld.lld unzip; do
    command -v "$tool" >/dev/null || die "$tool is not installed. Install clang, lld and unzip with your package manager and run this again."
  done
  command -v darling >/dev/null ||
    die "Darling is not installed. Build it with https://docs.darlinghq.org/build-instructions.html and run this again."

  if [[ -d $DIR/.git ]]; then
    say "Updating Mac O' Blox"
    # Checkouts from before the move to this fork still point at the original
    # repository, which does not have its fixes.
    case $(git -C "$DIR" remote get-url origin 2>/dev/null) in
      https://github.com/narezy/MacOBlox | https://github.com/narezy/MacOBlox.git)
        git -C "$DIR" remote set-url origin "$REPO" ;;
    esac
    git -C "$DIR" pull --ff-only
  else
    say "Downloading Mac O' Blox"
    git clone --depth 1 "$REPO" "$DIR"
  fi
  say "Building the Roblox shim"
  local output
  if ! output=$("$DIR/build_debug_shim.sh" 2>&1); then
    printf '%s\n' "$output" >&2
    die "Could not build the shim. Send the text above to the Discord: https://discord.gg/jCjHYYNq48"
  fi
  "$DIR/launcher/install.sh"
  say "Done. Open Mac O' Blox from the app menu, press Install Roblox, then Play."
}

# ---------------------------------------------------------------- uninstall

# The checkout this script makes: nothing is deleted unless $DIR is one.
is_installed() { [[ -f $DIR/launcher/macoblox-launcher && -f $DIR/build_debug_shim.sh ]]; }
installed_version() { sed -n 's/^__version__ = "\(.*\)"/\1/p' "$DIR/launcher/macoblox/__init__.py" 2>/dev/null; }

# Removes what do_install and the launcher put on this computer; with an
# argument, Darling's prefix as well. Darling and the other packages stay.
do_uninstall() {
  local purge=${1:-}
  if [[ -e $DIR ]] && ! is_installed; then
    die "$DIR does not look like Mac O' Blox, so it is left alone."
  fi
  # Nothing in the prefix may change under a running Darling (it keeps
  # showing deleted files), and nothing should run from the folder that goes.
  if pgrep -u "$(id -u)" -x darlingserver >/dev/null 2>&1; then
    say "Stopping Roblox and Darling"
    darling shutdown >/dev/null 2>&1 || true
  fi
  if [[ -x $DIR/studio/wine/bin/wineserver ]]; then
    WINEPREFIX=$DIR/studio/prefix "$DIR/studio/wine/bin/wineserver" -k >/dev/null 2>&1 || true
  fi
  if [[ -e $DIR ]]; then
    say "Removing the launcher, Roblox and Studio (${DIR/#$HOME/\~})"
    rm -rf -- "$DIR"
  fi
  say "Removing the app menu entries, icons and the macoblox command"
  local apps=$DATA_HOME/applications
  # The xyz.narez.* names are the app ID before 0.15.
  rm -f -- "$apps/wtf.aubree.MacOBlox.desktop" "$apps/wtf.aubree.MacOBlox.URI.desktop" \
    "$apps/wtf.aubree.MacOBlox.Studio.desktop" \
    "$apps/xyz.narez.MacOBlox.desktop" "$apps/xyz.narez.MacOBlox.Studio.desktop" \
    "$apps/macoblox-roblox-window.desktop" "$apps/org.macoblox.Launcher.desktop" \
    "$DATA_HOME"/icons/hicolor/*/apps/macoblox.png "$DATA_HOME/mime/packages/wtf.aubree.MacOBlox.xml" \
    "$DATA_HOME/mime/packages/xyz.narez.MacOBlox.xml"
  local link=$HOME/.local/bin/macoblox
  if [[ -L $link && $(readlink "$link") == */macoblox-launcher ]]; then
    rm -f -- "$link"
  fi
  # Studio as the handler of roblox-studio: links and place files.
  if [[ -f $CONFIG_HOME/mimeapps.list ]]; then
    sed -i -e 's/wtf\.aubree\.MacOBlox\.Studio\.desktop;\{0,1\}//g' \
      -e 's/wtf\.aubree\.MacOBlox\.URI\.desktop;\{0,1\}//g' \
      -e 's/xyz\.narez\.MacOBlox\.Studio\.desktop;\{0,1\}//g' -e '/^[^=[]*=$/d' "$CONFIG_HOME/mimeapps.list"
  fi
  update-mime-database "$DATA_HOME/mime" >/dev/null 2>&1 || true
  update-desktop-database "$apps" >/dev/null 2>&1 || true
  say "Removing settings and cache"
  rm -rf -- "$CONFIG_HOME/macoblox" "$CACHE_HOME/macoblox"
  if [[ -n $purge && -e $PREFIX ]]; then
    [[ $PREFIX == "$HOME"/?* ]] || die "Darling's prefix $PREFIX is not in your home folder, so it is left alone."
    say "Removing Darling's prefix (${PREFIX/#$HOME/\~}), with your Roblox sign-in"
    rm -rf -- "$PREFIX"
  fi
  say "Mac O' Blox is uninstalled."
  if command -v darling >/dev/null; then
    printf '    %sDarling stays installed; remove it with your package manager if nothing else uses it.%s\n' \
      "$DIM" "$RESET"
  fi
}

# --------------------------------------------------------------------- menu

# Drawn on the terminal's alternate screen, which gets its old contents back
# when the menu closes.
MENU_ON=''
menu_open() {
  MENU_ON=1
  printf '\033[?1049h\033[?25l' >/dev/tty
}
menu_close() {
  [[ -n $MENU_ON ]] || return 0
  MENU_ON=''
  printf '\033[?25h\033[?1049l' >/dev/tty
}

banner() {
  local line shade=0
  while IFS= read -r line; do
    printf '  %s%s%s\n' "${SHADES[shade]}" "$line" "$RESET"
    shade=$((shade + 1))
  done <<'ART'
 __  __          ___ _   ___ _
|  \/  |__ _ __ / _ ( ) | _ ) |_____ __
| |\/| / _` / _| (_) |/  | _ \ / _ \ \ /
|_|  |_\__,_\__|\___/    |___/_\___/_\_\
ART
}

# choose TEXT ITEM...: a menu of "label|hint" items below TEXT (printf %b).
# Sets CHOICE to the chosen item's index, or to -1 for quit.
CHOICE=-1
choose() {
  local text=$1
  shift
  local count=$# index=0 key rest item label hint i
  while :; do
    {
      printf '\033[H\033[2J\n'
      banner
      printf '\n%b\n\n' "$text"
      i=0
      for item; do
        label=${item%%|*}
        hint=${item#*|}
        if ((i == index)); then
          printf '  %s %s %-22s%s %s\n' "$SELECTED" "$POINTER" "$label" "$RESET" "$hint"
        else
          printf '     %-22s %s%s%s\n' "$label" "$DIM" "$hint" "$RESET"
        fi
        i=$((i + 1))
      done
      printf '\n  %s%s%s\n' "$DIM" "$KEYS" "$RESET"
    } >/dev/tty
    IFS= read -rsn1 key </dev/tty || { CHOICE=-1; return; }
    case $key in
      $'\033')
        rest=''
        IFS= read -rsn2 -t 0.05 rest </dev/tty || true
        case $rest in
          '[A' | 'OA') index=$(((index + count - 1) % count)) ;;
          '[B' | 'OB') index=$(((index + 1) % count)) ;;
          '') CHOICE=-1; return ;;
        esac ;;
      k | K) index=$(((index + count - 1) % count)) ;;
      j | J) index=$(((index + 1) % count)) ;;
      [1-9]) if ((key <= count)); then CHOICE=$((key - 1)); return; fi ;;
      q | Q) CHOICE=-1; return ;;
      '') CHOICE=$index; return ;;
    esac
  done
}

menu_main() {
  local status first="Install|Darling, the tools, the launcher and its menu entry"
  if is_installed; then
    status="  ${GOOD}${ON}${RESET} Mac O' Blox $(installed_version) is installed in ${DIR/#$HOME/\~}"
    first="Update|the latest version, rebuilt"
  else
    status="  ${DIM}${OFF} Not installed yet${RESET}"
  fi
  choose "  ${BOLD}The real macOS Roblox client on Linux, through Darling.${RESET}\n\n$status" \
    "$first" "Uninstall|remove Mac O' Blox from this computer" "Quit|"
}

# The uninstall screen. Sets PURGE; false for "back".
PURGE=''
menu_uninstall() {
  local where=${DIR/#$HOME/\~} prefix=${PREFIX/#$HOME/\~}
  choose "  ${BOLD}Uninstall removes${RESET}
    ${BULLET} $where (the launcher, Roblox, Studio)
    ${BULLET} the app menu entries, icons and the macoblox command
    ${BULLET} settings and cache

  ${DIM}Darling stays installed. Its prefix, $prefix, holds your Roblox sign-in.${RESET}" \
    "Uninstall|keep $prefix" "Uninstall everything|also delete $prefix" "Back|"
  case $CHOICE in
    0)
      PURGE=''
      return 0 ;;
    1)
      choose "  ${BAD}Delete $prefix?${RESET}

  It is Darling's macOS home folder: your Roblox sign-in, and anything
  else installed or saved in Darling, goes with it." \
        "No, go back|" "Yes, delete it|"
      [[ $CHOICE == 1 ]] || return 1
      PURGE=1
      return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<USAGE
Mac O' Blox installer

  install.sh               a menu in a terminal; without one, install or update
  install.sh --install     install or update
  install.sh --uninstall   remove Mac O' Blox (asks first, unless --yes)
  install.sh --uninstall --purge
                           also delete Darling's prefix, ${PREFIX/#$HOME/\~} (your Roblox sign-in)

With curl, options go after "bash -s --":
  curl -fsSL https://raw.githubusercontent.com/aubree-lat/MacOBlox/main/install.sh | bash -s -- --uninstall
USAGE
}

main() {
  local action='' assume_yes='' arg
  for arg in "$@"; do
    case $arg in
      --install) action=install ;;
      --uninstall) action=uninstall ;;
      --purge) PURGE=1 ;;
      -y | --yes) assume_yes=1 ;;
      -h | --help)
        usage
        return 0 ;;
      *) die "Unknown option: $arg (see --help)" ;;
    esac
  done
  # Package managers may ask questions; with curl | bash stdin is this script.
  if [[ ! -t 0 ]] && (: </dev/tty) 2>/dev/null; then exec </dev/tty; fi
  [[ $EUID -ne 0 ]] || die "Run this as your user, not root. sudo is used when needed."
  local terminal=''
  [[ -t 0 && -t 1 ]] && terminal=1

  if [[ -z $action && -n $terminal ]]; then
    trap 'menu_close' EXIT
    trap 'menu_close; exit 130' INT TERM
    menu_open
    while [[ -z $action ]]; do
      menu_main
      case $CHOICE in
        0) action=install ;;
        1) if menu_uninstall; then action=uninstall; fi ;;
        *) action=quit ;;
      esac
    done
    menu_close
    [[ $action == quit ]] || banner
  elif [[ $action == uninstall && -z $assume_yes ]]; then
    [[ -n $terminal ]] || die "Not uninstalling without a terminal to ask in; add --yes."
    local answer='' what="Mac O' Blox"
    [[ -n $PURGE ]] && what+=" and Darling's prefix ${PREFIX/#$HOME/\~}"
    printf 'Remove %s? [y/N] ' "$what"
    IFS= read -r answer || true
    if [[ $answer != [Yy]* ]]; then
      say "Nothing removed."
      return 0
    fi
  fi

  case ${action:-install} in
    install) do_install ;;
    uninstall) do_uninstall "$PURGE" ;;
    quit) ;;
  esac
}

main "$@"; exit
