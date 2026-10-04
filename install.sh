#!/usr/bin/env bash
# Mac O' Blox installer: Darling, the tools the launcher needs, and the
# launcher itself with its app menu entry. Run it again to update, or to
# uninstall.
#
#   curl -fsSL https://raw.githubusercontent.com/aubree-lat/MacOBlox/main/install.sh | bash
#
# In a terminal it guides setup; without one it installs. The choices
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

say() { printf '  %s%s%s %s\n' "$ACCENT" "$BULLET" "$RESET" "$*"; }
die() { printf '%sError:%s %s\n' "$BAD" "$RESET" "$*" >&2; exit 1; }
UPDATE_BACKUP=''
INSTALL_LOG=''

step() { printf '\n%s[%s/4] %s%s\n' "$BOLD" "$1" "$2" "$RESET"; }

distribution_name() {
  local PRETTY_NAME='' ID='' ID_LIKE=''
  [[ ! -r /etc/os-release ]] || . /etc/os-release
  printf '%s' "${PRETTY_NAME:-Linux}"
}

setup_plan() {
  local operation='Install' dependencies='your package manager'
  is_installed && operation='Update'
  if command -v pacman >/dev/null; then dependencies='pacman and the AUR'
  elif command -v apt-get >/dev/null; then dependencies='apt'
  elif command -v dnf >/dev/null; then dependencies='dnf'
  fi
  printf '  %sSetup plan%s\n\n' "$BOLD" "$RESET"
  printf '    1. Prepare Darling and the system tools (%s).\n' "$dependencies"
  printf '    2. %s the Mac O\047 Blox launcher.\n' "$operation"
  printf '    3. Build its compatibility libraries.\n'
  printf '    4. Add the app menu entry and macoblox command.\n\n'
  printf '  Computer    %s (%s)\n' "$(distribution_name)" "$(uname -m)"
  printf '  Destination %s\n' "${DIR/#$HOME/\~}"
  printf '  %sSystem packages may ask for your sudo password.%s\n' "$DIM" "$RESET"
  if is_installed; then
    printf '  %sUpdates keep settings, Roblox, Studio and existing backups.%s\n' "$DIM" "$RESET"
    printf '  %sLocal source changes are backed up before replacement.%s\n' "$DIM" "$RESET"
  else
    printf '  %sFirst launch guides Roblox installation and sign-in.%s\n' "$DIM" "$RESET"
  fi
}

# Keep recovery material outside the checkout. A reset can remove untracked
# files that obstruct incoming tracked paths; back those up too, and leave
# other untracked/ignored files in place instead of using git clean.
backup_checkout_changes() {
  local list_dir relative backup
  list_dir=$(mktemp -d)
  git -C "$DIR" diff --name-only -z HEAD > "$list_dir/tracked"
  git -C "$DIR" ls-files --others --exclude-standard -z > "$list_dir/untracked"
  if [[ ! -s $list_dir/tracked && ! -s $list_dir/untracked ]]; then
    rm -rf -- "$list_dir"
    return
  fi
  backup=$(umask 077; mkdir -p -- "$DATA_HOME/MacOBlox-backups";
    mktemp -d "$DATA_HOME/MacOBlox-backups/update-$(date -u +%Y%m%d-%H%M%S)-XXXXXX")
  git -C "$DIR" rev-parse HEAD > "$backup/revision"
  git -C "$DIR" diff --binary HEAD > "$backup/tracked.patch"
  cp -- "$list_dir/tracked" "$backup/tracked-paths"
  cp -- "$list_dir/untracked" "$backup/untracked-paths"
  while IFS= read -r -d '' relative; do
    [[ -e $DIR/$relative || -L $DIR/$relative ]] || continue
    mkdir -p -- "$backup/files/$(dirname -- "$relative")"
    cp -a -- "$DIR/$relative" "$backup/files/$relative"
  done < <(cat -- "$list_dir/tracked" "$list_dir/untracked")
  rm -rf -- "$list_dir"
  UPDATE_BACKUP=$backup
  say "Local changes saved to ${backup/#$HOME/\~}"
}

setup_success() {
  local version
  version=$(installed_version)
  printf '\n%s%s Setup complete%s\n' "$GOOD" "$ON" "$RESET"
  printf '  Mac O\047 Blox%s is ready in your app menu.\n' "${version:+ $version}"
  printf '\n  %sNext steps%s\n' "$BOLD" "$RESET"
  printf '    1. Open Mac O\047 Blox from the app menu, or run macoblox.\n'
  if [[ -d $DIR/RobloxPlayer.app ]]; then
    printf '    2. Launch Roblox from the launcher.\n'
    printf '    3. Sign in if needed, then choose a game.\n'
  else
    printf '    2. Follow its welcome screen to install Roblox.\n'
    printf '    3. Sign in to Roblox and choose a game.\n'
  fi
  [[ -z $UPDATE_BACKUP ]] || printf '\n  Source backup: %s\n' "${UPDATE_BACKUP/#$HOME/\~}"
  [[ -z $INSTALL_LOG ]] || printf '  Build log: %s\n' "${INSTALL_LOG/#$HOME/\~}"
  printf '\n'
}

# ------------------------------------------------------------------ install

install_arch() {
  # Only packages that are not installed at all: asking pacman for an
  # installed but outdated one (pipewire-audio 1.6.8 with 1.6.9 in the repo)
  # makes it a partial upgrade that breaks on pinned dependencies.
  local wanted=(git base-devel clang lld unzip python python-gobject gtk4 libadwaita webkitgtk-6.0 sdl2-compat wayland pkgconf)
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
    gir1.2-gtk-4.0 gir1.2-adw-1 gir1.2-webkit-6.0 libsdl2-dev libwayland-dev pkg-config
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
  sudo dnf install -y git clang lld unzip pipewire-utils python3-gobject gtk4 libadwaita webkitgtk6.0 SDL2-devel wayland-devel pkgconf-pkg-config
}

do_install() {
  [[ $(uname -m) == x86_64 ]] || die "Darling runs only on x86_64."
  [[ ! -e $DIR || -d $DIR/.git ]] ||
    die "$DIR already exists without a Git checkout. Move it aside before installing."
  step 1 "Prepare the system tools"
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
  for tool in git clang ld.lld unzip; do
    command -v "$tool" >/dev/null || die "$tool is not installed. Install git, clang, lld and unzip with your package manager and run this again."
  done
  command -v darling >/dev/null ||
    die "Darling is not installed. Build it with https://docs.darlinghq.org/build-instructions.html and run this again."

  step 2 "Prepare Mac O' Blox"
  if [[ -d $DIR/.git ]]; then
    say "Updating Mac O' Blox"

    # Checkouts from before the move to this fork still point at the original
    # repository, which does not have its fixes.
    case $(git -C "$DIR" remote get-url origin 2>/dev/null) in
      https://github.com/narezy/MacOBlox | https://github.com/narezy/MacOBlox.git)
        git -C "$DIR" remote set-url origin "$REPO" ;;
    esac

    # Fetch first, then preserve local repairs before replacing tracked files.
    # Session data, downloads and backups stay in the checkout unchanged.
    git -C "$DIR" fetch origin main
    backup_checkout_changes
    git -C "$DIR" reset --hard origin/main

  else
    say "Downloading Mac O' Blox"
    git clone --depth 1 "$REPO" "$DIR"
  fi
  step 3 "Build the compatibility libraries"
  say "This can take a few minutes."
  mkdir -p -- "$CACHE_HOME/macoblox/installer"
  INSTALL_LOG=$(umask 077; mktemp "$CACHE_HOME/macoblox/installer/build-$(date -u +%Y%m%d-%H%M%S)-XXXXXX.log")
  if ! "$DIR/build_debug_shim.sh" > "$INSTALL_LOG" 2>&1; then
    tail -n 40 -- "$INSTALL_LOG" >&2
    die "Build failed. Full log: $INSTALL_LOG. Help: https://discord.gg/jCjHYYNq48"
  fi
  say "Compatibility libraries built."
  step 4 "Add the launcher to your desktop"
  "$DIR/launcher/install.sh"
  setup_success
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
MENU_SCREEN=''
menu_open() {
  MENU_ON=1
  if [[ ${TERM:-dumb} != dumb ]]; then
    MENU_SCREEN=1
    printf '\033[?1049h\033[?25l' >/dev/tty
  fi
}
menu_close() {
  [[ -n $MENU_ON ]] || return 0
  MENU_ON=''
  if [[ -n $MENU_SCREEN ]]; then
    MENU_SCREEN=''
    printf '\033[?25h\033[?1049l' >/dev/tty
  fi
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
  if [[ -z $MENU_SCREEN ]]; then
    {
      banner
      printf '\n%b\n\n' "$text"
      i=1
      for item; do
        printf '  %s. %s  %s\n' "$i" "${item%%|*}" "${item#*|}"
        i=$((i + 1))
      done
    } >/dev/tty
    while :; do
      printf '\n  Choose 1-%s [1], or q to quit: ' "$count" >/dev/tty
      IFS= read -r key </dev/tty || { CHOICE=-1; return; }
      [[ -n $key ]] || key=1
      case $key in
        q | Q) CHOICE=-1; return ;;
        [1-9]) if ((key <= count)); then CHOICE=$((key - 1)); return; fi ;;
      esac
    done
  fi
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
  local text first="Start setup|Review what will be installed"
  if is_installed; then
    text="  ${BOLD}Welcome back to Mac O' Blox${RESET}

  ${GOOD}${ON}${RESET} Version $(installed_version) is installed.
  Keep your launcher and compatibility libraries up to date.
  ${DIM}${DIR/#$HOME/\~}${RESET}"
    first="Update Mac O' Blox|Review the update plan"
  else
    text="  ${BOLD}Welcome to Mac O' Blox${RESET}
  ${DIM}First setup · 1 of 3${RESET}

  Play the macOS Roblox client on your Linux desktop.
  We'll prepare the launcher, Darling and the system tools.
  The launcher will guide you through installing Roblox and signing in."
  fi
  choose "$text" "$first" "Uninstall|Remove Mac O' Blox from this computer" "Quit|"
}

menu_install() {
  local operation='Install'
  is_installed && operation='Update'
  while :; do
    choose "  ${BOLD}Setup · 2 of 3${RESET}

$(setup_plan)" "Continue|Confirm this setup plan" "Back|Return to the welcome screen"
    [[ $CHOICE == 0 ]] || return 1
    choose "  ${BOLD}Ready to ${operation,,} Mac O' Blox${RESET}
  ${DIM}Setup · 3 of 3${RESET}

  Destination: ${DIR/#$HOME/\~}
  Setup downloads the launcher and builds the compatibility libraries.
  You'll see progress for each step. System packages may request sudo.

  ${DIM}Begin when you're ready.${RESET}" \
      "$operation Mac O' Blox|Begin setup" "Back|Review the plan again"
    case $CHOICE in
      0) return 0 ;;
      1) ;;
      *) return 1 ;;
    esac
  done
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
  install.sh --install     review the setup plan, then install or update
  install.sh --update      same as --install
  install.sh --install --yes
                           install or update without setup prompts
  install.sh --uninstall   remove Mac O' Blox (asks first, unless --yes)
  install.sh --uninstall --purge
                           also delete Darling's prefix, ${PREFIX/#$HOME/\~} (your Roblox sign-in)

With curl, options go after "bash -s --":
  curl -fsSL https://raw.githubusercontent.com/aubree-lat/MacOBlox/main/install.sh | bash -s -- --uninstall
USAGE
}

main() {
  local action='' assume_yes='' reviewed='' arg
  for arg in "$@"; do
    case $arg in
      --install | --update) action=install ;;
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

  if [[ -z $action && -n $terminal && -z $assume_yes ]]; then
    trap 'menu_close' EXIT
    trap 'menu_close; exit 130' INT TERM
    menu_open
    while [[ -z $action ]]; do
      menu_main
      case $CHOICE in
        0) if menu_install; then action=install; reviewed=1; fi ;;
        1) if menu_uninstall; then action=uninstall; fi ;;
        *) action=quit ;;
      esac
    done
    menu_close
    [[ $action == quit ]] || banner
  elif [[ $action == install && -n $terminal && -z $assume_yes ]]; then
    trap 'menu_close' EXIT
    trap 'menu_close; exit 130' INT TERM
    menu_open
    if ! menu_install; then
      menu_close
      say "Setup cancelled."
      return 0
    fi
    reviewed=1
    menu_close
    banner
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
    install)
      if [[ -z $reviewed ]]; then
        banner
        printf '\n'
        setup_plan
      fi
      do_install ;;
    uninstall) do_uninstall "$PURGE" ;;
    quit) ;;
  esac
}

main "$@"; exit
