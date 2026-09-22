#!/usr/bin/env bash
# Relaunches Numbers while skipping window/document restoration. Try this first
# when Numbers is freezing on launch — a common cause is a pile-up of orphaned
# blank documents from interrupted AppleScript runs (an AppleScript timeout only
# stops the caller from waiting, it doesn't cancel the operation on Numbers'
# side), which Numbers then tries to restore all of on next launch.
#
# If this launches cleanly with no restored documents, that confirms the pile-up
# theory. If it still hangs, escalate to scripts/reset-numbers-prefs.sh or
# scripts/reset-numbers.sh.

echo "=== Quit Numbers ==="
osascript -e 'tell application "Numbers" to quit' 2>/dev/null
sleep 2
pkill -9 -f "Numbers Creator Studio" 2>/dev/null || true
pkill -9 -f "com.apple.Numbers" 2>/dev/null || true

echo "=== Relaunching without restoring previous windows/documents ==="
open -a "Numbers" --args -ApplePersistenceIgnoreState YES
