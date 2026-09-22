#!/usr/bin/env bash
# Aggressively resets Numbers when it starts hanging/freezing on basic operations
# (including AppleScript-driven ones this app depends on for exporting).
#
# Goes beyond Numbers' own preferences/container to also clear shared iWork
# resources, reset its Automation (TCC) consent, and rebuild its Launch Services
# registration. Run this, then reinstall/relaunch Numbers manually from
# Finder/Dock (not via AppleScript) and let it fully finish first-run setup
# before exporting again.
#
# A common cause of freezing: repeated failed/interrupted AppleScript runs can
# leave orphaned blank documents open in the background (an AppleScript timeout
# only stops the caller from waiting — it doesn't cancel the operation on
# Numbers' side). On next launch Numbers tries to restore all of them, which can
# look like a hang. If that's the cause, relaunching with window restoration
# skipped is a faster fix than this full reset:
#   open -a "Numbers" --args -ApplePersistenceIgnoreState YES
#
# This script will prompt for your password (sudo), and you may see an
# Automation/TCC re-consent prompt the next time something scripts Numbers —
# both expected.

echo "=== 1. Quit Numbers and any related helpers ==="
osascript -e 'tell application "Numbers" to quit' 2>/dev/null
sleep 2
pkill -9 -f "Numbers Creator Studio" 2>/dev/null || true
pkill -9 -f "com.apple.Numbers" 2>/dev/null || true

echo "=== 2. Remove Numbers' own user-level state ==="
rm -f ~/Library/Preferences/com.apple.Numbers.plist
rm -rf ~/Library/Containers/com.apple.Numbers
rm -rf ~/Library/Saved\ Application\ State/com.apple.Numbers.savedState
rm -rf ~/Library/Caches/com.apple.Numbers
rm -rf ~/Library/HTTPStorages/com.apple.Numbers

echo "=== 3. Remove shared iWork resources (templates, cross-app state) ==="
# These App Group containers are shared across Keynote/Pages/Numbers and can hold
# stale template/catalog state that a single app's own container wipe won't touch.
find ~/Library/Group\ Containers -maxdepth 1 -iname "*iwork*" -print
find ~/Library/Group\ Containers -maxdepth 1 -iname "*iwork*" -exec rm -rf {} +

echo "=== 4. Clear any Numbers crash reports (may explain past hangs) ==="
find ~/Library/Logs/DiagnosticReports -iname "*Numbers*" -print
find ~/Library/Logs/DiagnosticReports -iname "*Numbers*" -delete

echo "=== 5. Reset Automation/TCC consent for Numbers ==="
tccutil reset AppleEvents com.apple.Numbers

echo "=== 6. Rebuild Launch Services registration for Numbers ==="
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -kill -r -domain local -domain system -domain user

echo
echo "=== Done. Now reinstall Numbers, then launch it manually from Finder/Dock ==="
echo "=== (not via AppleScript) and let it fully finish first-run setup before retesting. ==="
