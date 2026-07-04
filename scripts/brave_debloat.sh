#!/bin/zsh
set -e

# Derive the real user — when run via Authorization Services (no sudo wrapper),
# $SUDO_USER is empty. Fall back to the console owner.
SUDO_USER="${SUDO_USER:-$(stat -f%Su /dev/console)}"

echo "Closing Brave..."
sudo -u "$SUDO_USER" osascript -e 'tell application "Brave Browser" to quit' 2>/dev/null || true
sleep 2
pkill -f '/Applications/Brave Browser.app' 2>/dev/null || true

echo "Writing managed policies..."
mkdir -p "/Library/Managed Preferences"
chown root:wheel "/Library/Managed Preferences"
chmod 755 "/Library/Managed Preferences"

plist="/Library/Managed Preferences/com.brave.Browser.plist"
rm -f "$plist"
plutil -create xml1 "$plist"

/usr/libexec/PlistBuddy -c "Add :BraveRewardsDisabled bool true" "$plist"
/usr/libexec/PlistBuddy -c "Add :BraveWalletDisabled bool true" "$plist"
/usr/libexec/PlistBuddy -c "Add :BraveVPNDisabled bool true" "$plist"
/usr/libexec/PlistBuddy -c "Add :BraveAIChatEnabled bool false" "$plist"
/usr/libexec/PlistBuddy -c "Add :BraveNewsDisabled bool true" "$plist"
/usr/libexec/PlistBuddy -c "Add :BraveTalkDisabled bool true" "$plist"
/usr/libexec/PlistBuddy -c "Add :BravePlaylistEnabled bool false" "$plist"
/usr/libexec/PlistBuddy -c "Add :BraveSpeedreaderEnabled bool false" "$plist"
/usr/libexec/PlistBuddy -c "Add :BraveWaybackMachineEnabled bool false" "$plist"
/usr/libexec/PlistBuddy -c "Add :BraveP3AEnabled bool false" "$plist"
/usr/libexec/PlistBuddy -c "Add :BraveStatsPingEnabled bool false" "$plist"
/usr/libexec/PlistBuddy -c "Add :BraveWebDiscoveryEnabled bool false" "$plist"

chown root:wheel "$plist"
chmod 644 "$plist"

echo "Restarting preference daemons..."
killall cfprefsd 2>/dev/null || true
sudo -u "$SUDO_USER" killall cfprefsd 2>/dev/null || true

echo "Launching Brave to verify..."
sudo -u "$SUDO_USER" open -a "Brave Browser" "brave://policy"

echo "Done. Brave managed debloat policies installed."
