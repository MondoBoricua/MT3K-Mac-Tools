#!/bin/zsh
set -e

# Derive the real user — when run via Authorization Services (no sudo wrapper),
# $SUDO_USER is empty. Fall back to the console owner.
SUDO_USER="${SUDO_USER:-$(stat -f%Su /dev/console)}"
REAL_HOME="$(eval echo "~$SUDO_USER")"

echo "Closing Brave..."
sudo -u "$SUDO_USER" osascript -e 'tell application "Brave Browser" to quit' 2>/dev/null || true
sleep 2
pkill -f '/Applications/Brave Browser.app' 2>/dev/null || true

echo "Removing Brave machine/user policy files..."
rm -f \
  "/Library/Managed Preferences/com.brave.Browser.plist" \
  "/Library/Managed Preferences/$SUDO_USER/com.brave.Browser.plist" \
  "/Library/Preferences/com.brave.Browser.plist" \
  "/var/root/Library/Preferences/com.brave.Browser.plist"

find "/Library/Preferences/ByHost" -maxdepth 1 -name 'com.brave.Browser*.plist' -delete 2>/dev/null || true
find "/var/root/Library/Preferences/ByHost" -maxdepth 1 -name 'com.brave.Browser*.plist' -delete 2>/dev/null || true

echo "Deleting any CFPreferences domains..."
defaults delete "/Library/Managed Preferences/com.brave.Browser" 2>/dev/null || true
defaults delete "/Library/Managed Preferences/$SUDO_USER/com.brave.Browser" 2>/dev/null || true
defaults delete "/Library/Preferences/com.brave.Browser" 2>/dev/null || true
defaults delete com.brave.Browser 2>/dev/null || true

if [[ -n "$SUDO_USER" ]]; then
  sudo -u "$SUDO_USER" defaults delete com.brave.Browser 2>/dev/null || true
fi

echo "Restarting preference daemons..."
killall cfprefsd 2>/dev/null || true
if [[ -n "$SUDO_USER" ]]; then
  sudo -u "$SUDO_USER" killall cfprefsd 2>/dev/null || true
fi

echo "Remaining Brave preference/policy files:"
find "/Library/Managed Preferences" "/Library/Preferences" "/var/root/Library/Preferences" "$REAL_HOME/Library/Preferences" \
  -maxdepth 3 -name '*brave*' -print 2>/dev/null || true

echo "Opening Brave policy page..."
if [[ -n "$SUDO_USER" ]]; then
  sudo -u "$SUDO_USER" open -a "Brave Browser" "brave://policy"
else
  open -a "Brave Browser" "brave://policy"
fi

echo "Done. If policies still show, press Reload policies in brave://policy or reboot macOS once."
