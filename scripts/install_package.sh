#!/bin/zsh
set -e

kind="$1"
shift || true

# Locate brew
if [ -x /opt/homebrew/bin/brew ]; then
  BREW=/opt/homebrew/bin/brew
elif [ -x /usr/local/bin/brew ]; then
  BREW=/usr/local/bin/brew
else
  BREW="$(command -v brew 2>/dev/null || true)"
fi

if [ -n "$BREW" ]; then
  eval "$("$BREW" shellenv)" 2>/dev/null || true
fi

NPM="$(command -v npm 2>/dev/null || true)"

# NOTE: casks with .pkg artifacts (Wireshark, Zoom, Teams, etc.) are not
# installed via this dispatcher — Swift detects `requiresAdminInstall: true`
# and opens Terminal.app with the brew command. Terminal gives sudo a real
# TTY so macOS can prompt for the password the standard way.

# install_dmg_from_url <dmg-url>
# Downloads, mounts, copies the .app to /Applications, strips quarantine, detaches.
install_dmg_from_url() {
  local url="$1"
  local tmp mnt app appname
  tmp=$(mktemp -d)
  mnt=""
  trap 'rm -rf "$tmp"; [ -n "$mnt" ] && hdiutil detach "$mnt" -quiet 2>/dev/null || true' EXIT

  echo "→ Descargando $(basename "$url")..."
  curl -fL --progress-bar "$url" -o "$tmp/installer.dmg"

  echo "→ Montando .dmg..."
  mnt=$(hdiutil attach "$tmp/installer.dmg" -nobrowse -noverify -noautoopen | grep -E '\s/Volumes/' | tail -1 | awk '{$1=$2=""; sub(/^ +/,""); print}')
  [ -z "$mnt" ] && { echo "Error: no se pudo montar el .dmg"; exit 1; }
  echo "  montado en: $mnt"

  app=$(find "$mnt" -maxdepth 2 -name '*.app' -type d | head -1)
  [ -z "$app" ] && { echo "Error: no se encontró .app en el .dmg"; exit 1; }
  appname=$(basename "$app")
  echo "→ Copiando $appname a /Applications..."
  rm -rf "/Applications/$appname"
  cp -R "$app" "/Applications/"

  echo "→ Quitando quarantine..."
  xattr -dr com.apple.quarantine "/Applications/$appname" 2>/dev/null || true

  echo "→ Desmontando..."
  hdiutil detach "$mnt" -quiet
  mnt=""

  echo "✓ $appname instalado en /Applications/"
}

case "$kind" in
  cask)
    [ -z "$BREW" ] && { echo "Error: Homebrew no encontrado"; exit 1; }
    echo "→ brew install --cask $@"
    "$BREW" install --cask "$@"
    ;;
  upgrade-cask)
    [ -z "$BREW" ] && { echo "Error: Homebrew no encontrado"; exit 1; }
    echo "→ brew upgrade --cask $@"
    "$BREW" upgrade --cask "$@"
    ;;
  formula)
    [ -z "$BREW" ] && { echo "Error: Homebrew no encontrado"; exit 1; }
    echo "→ brew install $@"
    "$BREW" install "$@"
    ;;
  upgrade-formula)
    [ -z "$BREW" ] && { echo "Error: Homebrew no encontrado"; exit 1; }
    echo "→ brew upgrade $@"
    "$BREW" upgrade "$@"
    ;;
  tap)
    [ -z "$BREW" ] && { echo "Error: Homebrew no encontrado"; exit 1; }
    echo "→ brew install $@"
    "$BREW" install "$@"
    ;;
  upgrade-tap)
    [ -z "$BREW" ] && { echo "Error: Homebrew no encontrado"; exit 1; }
    echo "→ brew upgrade $@"
    "$BREW" upgrade "$@"
    ;;
  npm)
    [ -z "$NPM" ] && { echo "Error: npm no encontrado. Instalá Node.js primero."; exit 1; }
    echo "→ npm install -g $@"
    "$NPM" install -g "$@"
    ;;
  dmg)
    # Args: <arm64-url> <x64-url>
    arch=$(uname -m)
    if [ "$arch" = "arm64" ]; then url="$1"; else url="$2"; fi
    [ -z "$url" ] && { echo "Error: no hay URL para arch $arch"; exit 1; }
    install_dmg_from_url "$url"
    ;;
  github-latest)
    # Args: <owner/repo> <arm-pattern-regex> <intel-pattern-regex>
    repo="$1"; arm_pat="$2"; intel_pat="$3"
    arch=$(uname -m)
    pat="$intel_pat"
    [ "$arch" = "arm64" ] && pat="$arm_pat"

    echo "→ Resolviendo última release de $repo..."
    api="https://api.github.com/repos/$repo/releases/latest"
    url=$(curl -fsSL "$api" \
          | grep -oE '"browser_download_url": *"[^"]*"' \
          | sed -E 's/^"browser_download_url": *"//; s/"$//' \
          | grep -E "$pat" | head -1)
    [ -z "$url" ] && { echo "Error: ningún asset coincide con '$pat'"; exit 1; }
    echo "  → $(basename "$url")"
    install_dmg_from_url "$url"
    ;;
  *)
    echo "Error: tipo desconocido '$kind' (usá cask, upgrade-cask, formula, upgrade-formula, tap, upgrade-tap, npm, dmg, github-latest)"
    exit 1
    ;;
esac

echo "✓ Hecho."
