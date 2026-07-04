#!/usr/bin/env bash
set -euo pipefail

# MT3K Mac Tools — first-time setup
# Usage: ./setup.sh

echo "=== MT3K Mac Tools Setup ==="
echo ""

# --- macOS version check (requires 14+) -------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: MT3K Mac Tools only builds and runs on macOS." >&2
  exit 1
fi

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$macos_major" -lt 14 ]]; then
  echo "Error: macOS 14 (Sonoma) or newer is required. Found $(sw_vers -productVersion)." >&2
  exit 1
fi
echo "macOS $(sw_vers -productVersion) detected."

# --- Xcode Command Line Tools -----------------------------------------------
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Error: Xcode Command Line Tools not found." >&2
  echo "Install them with: xcode-select --install" >&2
  exit 1
fi
echo "Xcode Command Line Tools found at $(xcode-select -p)."

# --- Swift 6 toolchain -------------------------------------------------------
if ! command -v swift >/dev/null 2>&1; then
  echo "Error: 'swift' not found on PATH. Install Xcode or the Swift toolchain." >&2
  exit 1
fi

swift_version_line="$(swift --version 2>&1 | head -1)"
swift_major="$(echo "$swift_version_line" | grep -oE 'Swift version [0-9]+' | grep -oE '[0-9]+' || echo 0)"
if [[ "$swift_major" -lt 6 ]]; then
  echo "Error: Swift 6 or newer is required. Found: $swift_version_line" >&2
  echo "Update Xcode from the App Store, then re-run ./setup.sh." >&2
  exit 1
fi
echo "Found $swift_version_line"

# --- Build --------------------------------------------------------------------
echo ""
echo "Building (this resolves SwiftPM dependencies, first run may take a while)..."
swift build

echo ""
echo "=== Setup complete! ==="
echo ""
read -r -p "Build a debug .app bundle now with ./bundle.sh debug? [y/N] " reply
if [[ "$reply" =~ ^[Yy]$ ]]; then
  ./bundle.sh debug
fi

echo ""
echo "Next steps:"
echo "  1. Run:    swift run"
echo "  2. Or:     ./bundle.sh release && open \"dist/MT3K Mac Tools.app\""
echo "  3. Tests:  swift test"
echo "  4. Using Claude Code? CLAUDE.md has full project context."
