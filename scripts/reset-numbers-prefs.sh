#!/usr/bin/env bash
# Quick reset of Numbers' preferences/state — try this first when Numbers starts
# behaving oddly (hangs, stale settings). If it doesn't help, escalate to
# scripts/reset-numbers.sh, which also clears shared iWork resources, resets
# Automation/TCC consent, and rebuilds Launch Services registration.
#
# A common cause of freezing: repeated failed/interrupted AppleScript runs can
# leave orphaned blank documents open in the background (an AppleScript timeout
# only stops the caller from waiting — it doesn't cancel the operation on
# Numbers' side). On next launch Numbers tries to restore all of them, which can
# look like a hang. If that's the cause, this may be faster than either script:
#   open -a "Numbers" --args -ApplePersistenceIgnoreState YES

echo "=== Quit Numbers ==="
osascript -e 'tell application "Numbers" to quit' 2>/dev/null
sleep 2
pkill -9 -f "Numbers Creator Studio" 2>/dev/null || true
pkill -9 -f "com.apple.Numbers" 2>/dev/null || true

echo "=== Remove preferences, container, saved window state, and cache ==="
rm -f ~/Library/Preferences/com.apple.Numbers.plist
rm -rf ~/Library/Containers/com.apple.Numbers
rm -rf ~/Library/Saved\ Application\ State/com.apple.Numbers.savedState
rm -rf ~/Library/Caches/com.apple.Numbers

echo
echo "=== Done. Launch Numbers manually from Finder/Dock (not via AppleScript) ==="
echo "=== and let it fully finish first-run setup before retesting. ==="
